# Shared source-snapshot preparation. Windows PowerShell 5.1; no network or Git dependency.
. (Join-Path $PSScriptRoot 'eui-install-safety.ps1')

function Assert-EuiPortableArchive([string]$Archive, [string]$Target) {
    if ($Target -cnotin @('new-features','12.1.7-PTR-features')) { throw 'Unknown portable target.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        if (-not $zip.Entries.Count) { throw 'Empty snapshot ZIP.' }
        $root = ($zip.Entries[0].FullName.Replace('\','/') -split '/')[0]
        $valid = $root -ceq ('EllesmereUI-' + $Target) -or
            $root -cmatch '^EllesmereUI-[0-9a-f]{40}$' -or
            $root -cmatch '^hellsy55-EllesmereUI-[0-9a-f]{7,40}$'
        if (-not $valid) { throw "Unapproved GitHub snapshot root: $root" }
    } finally { $zip.Dispose() }
    Assert-EuiArchive -ZipPath $Archive -ExpectedRoot $root
    return $root
}

function Get-EuiPortableSource([string]$Extracted, [string]$ExpectedRoot) {
    Assert-EuiName $ExpectedRoot
    Assert-EuiTree $Extracted
    $children = @(Get-ChildItem -LiteralPath $Extracted -Force)
    if ($children.Count -ne 1 -or -not $children[0].PSIsContainer -or $children[0].Name -cne $ExpectedRoot) { throw 'Extracted root differs from the validated archive.' }
    return Get-EuiChildPath $Extracted $ExpectedRoot
}

function Invoke-EuiWriteProbe([string]$AddOns) {
    # Called only after complete payload validation and before the portable transaction.
    $root = Assert-EuiPath $AddOns
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Probe destination must already exist.' }
    $probe = Get-EuiChildPath $root ('EUI-write-test-' + [guid]::NewGuid().ToString('N'))
    $owned = $false
    try {
        $null = New-Item -ItemType Directory -Path $probe -ErrorAction Stop
        $owned = $true
    } finally {
        if ($owned) {
            Assert-EuiTree $probe
            Remove-Item -LiteralPath $probe -ErrorAction Stop
        }
    }
}

function ConvertFrom-EuiPkgmeta([string]$Text) {
    $Text = $Text.TrimStart([char]0xFEFF)
    $result = @{ ignore = @(); 'move-folders' = @{}; externals = @{} }
    $seen = @{}; $section = ''; $external = ''
    foreach ($raw in ($Text -split "`r?`n")) {
        $line = ($raw -replace ' +#.*$', '').TrimEnd()
        if (-not $line.Trim() -or $line.TrimStart().StartsWith('#')) { continue }
        if ($line -match '[\t\x00]' -or $line -match '^(<<<<<<<|=======|>>>>>>>)') { throw 'Invalid pkgmeta whitespace or conflict marker.' }
        if ($line -match '^([a-z-]+):(?: (.+))?$') {
            $section = $Matches[1]; $value = $Matches[2]; $external = ''
            if ($seen.ContainsKey($section)) { throw "Duplicate pkgmeta directive: $section" }
            $seen[$section] = $true
            switch ($section) {
                'package-as' { Assert-EuiName $value; $result[$section] = $value }
                'enable-nolib-creation' {
                    if ($value -cne 'no') { throw 'Only enable-nolib-creation: no is supported.' }
                    $result[$section] = $value
                }
                { $_ -in 'ignore','move-folders','externals' } { if ($value) { throw "Expected block: $section" } }
                default { throw "Unsupported packaging directive: $section" }
            }
        } elseif ($section -eq 'ignore' -and $line -match '^  - (.+)$') {
            $value = ConvertTo-EuiPackagePath $Matches[1]
            if ($result.ignore -contains $value) { throw "Duplicate ignore: $value" }
            $result.ignore += $value
        } elseif ($section -eq 'move-folders' -and $line -match '^  ([^:]+): (.+)$') {
            $key = ConvertTo-EuiPackagePath $Matches[1]; $value = ConvertTo-EuiPackagePath $Matches[2]
            if ($result[$section].ContainsKey($key)) { throw "Duplicate move: $key" }
            $result[$section][$key] = $value
        } elseif ($section -eq 'externals' -and $line -match '^  ([^:]+):$') {
            $external = ConvertTo-EuiPackagePath $Matches[1]
            if ($result.externals.ContainsKey($external)) { throw "Duplicate external: $external" }
            $result.externals[$external] = @{}
        } elseif ($section -eq 'externals' -and $external -and $line -match '^    (url|tag|branch|type): (.+)$') {
            $key = $Matches[1]; $value = $Matches[2]
            if ($value -notmatch '^[A-Za-z0-9_./:@+-]+$' -or $result.externals[$external].ContainsKey($key)) { throw 'Unsupported external scalar or duplicate field.' }
            $result.externals[$external][$key] = $value
        } else { throw "Unsupported pkgmeta syntax: $line" }
    }
    if (-not $result.ContainsKey('package-as')) { throw 'Missing package-as.' }
    foreach ($entry in $result.externals.Values) { if (-not $entry.ContainsKey('url')) { throw 'External requires url.' } }
    return $result
}

function ConvertTo-EuiPackagePath([string]$Value) {
    # Literal paths only. Reject YAML features and glob rules instead of approximating them.
    if ($Value -notmatch '^[A-Za-z0-9_./-]+$' -or $Value.EndsWith('/')) { throw "Unsupported package path: $Value" }
    foreach ($part in $Value.Split('/')) { Assert-EuiName $part }
    return $Value
}

function Test-EuiPackageIgnored([string]$Path, $Meta) {
    foreach ($rule in $Meta.ignore) {
        if ($Path -ceq $rule -or $Path.StartsWith($rule + '/', [StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

function Get-EuiPackageDestination([string]$Path, $Meta) {
    if (Test-EuiPackageIgnored $Path $Meta) { return $null }
    $mapped = $Meta['package-as'] + '/' + $Path
    foreach ($src in $Meta['move-folders'].Keys) {
        if ($mapped -ceq $src -or $mapped.StartsWith($src + '/', [StringComparison]::Ordinal)) {
            return $Meta['move-folders'][$src] + $mapped.Substring($src.Length)
        }
    }
    return $mapped
}

function Assert-EuiSnapshotTocs([string]$Source, [string]$Target) {
    $policyPath = Join-Path $Source '.tools/toc_policy.json'
    $policy = [IO.File]::ReadAllText($policyPath) | ConvertFrom-Json
    if ($policy.schema -ne 1 -or $policy.targets.PSObject.Properties.Name -notcontains $Target) { throw 'Unknown TOC policy or target.' }
    $classes = @{}
    if (@($policy.classes.PSObject.Properties.Name | Sort-Object) -join ',' -cne 'camelot,embedded,retail,shared') { throw 'Unknown TOC classes.' }
    foreach ($group in $policy.classes.PSObject.Properties) {
        if (-not $group.Value.reason) { throw 'TOC classification requires a rationale.' }
        foreach ($name in $group.Value.paths) {
            $null = ConvertTo-EuiPackagePath $name
            if ($classes.ContainsKey($name)) { throw "Duplicate manifest classification: $name" }
            $classes[$name] = $group.Name
        }
    }
    $found = @{}
    foreach ($toc in Get-ChildItem -LiteralPath $Source -Recurse -File -Force | Where-Object { $_.Extension -ieq '.toc' }) {
        $name = $toc.FullName.Substring($Source.TrimEnd('\').Length + 1).Replace('\','/')
        if ($name -match '^(\.git|\.release|\.pkgmeta-cache)/') { continue }
        if (-not $classes.ContainsKey($name)) { throw "Unknown manifest: $name. Classify it in toc_policy.json." }
        $found[$name] = $true
        $headers = @{}
        foreach ($line in [IO.File]::ReadAllLines($toc.FullName)) {
            if ($line -match '^(<<<<<<<|=======|>>>>>>>|\|\|\|\|\|\|\|)') { throw "Conflict marker in $name" }
            if ($line -match '^##\s*([^:]+):\s*(.*?)\s*$') {
                $key = $Matches[1].Trim(); $value = $Matches[2]
                if ($headers.ContainsKey($key) -or $key -like 'Interface-*') { throw "Ambiguous header in $name" }
                $headers[$key] = $value
            }
        }
        $kind = $classes[$name]
        if ($kind -eq 'embedded') { continue }
        $retail = [string]$policy.targets.$Target; $camelot = [string]$policy.camelot_interface
        if ($retail -notmatch '^[1-9][0-9]*$' -or $camelot -notmatch '^[1-9][0-9]*$') { throw 'Invalid policy Interface.' }
        $expected = switch ($kind) { retail { $retail }; camelot { $camelot }; shared { "$retail, $camelot" } }
        if ($headers.Interface -cne $expected) { throw "Incompatible Interface in $name for $Target" }
        $allowed = switch ($kind) { retail { 'standard' }; camelot { 'camelot' }; shared { $null } }
        if (($allowed -and $headers.AllowLoadGameType -cne $allowed) -or (-not $allowed -and $headers.ContainsKey('AllowLoadGameType'))) { throw "Incompatible client restriction in $name" }
        $clients = if ($allowed) { @($allowed) } else { @('standard','camelot') }
        foreach ($client in ($headers.ExcludeLoadGameType -split '[,\s]+')) { if ($client -and $clients -contains $client) { throw "Excluded classified client in $name" } }
    }
    foreach ($name in $classes.Keys) { if (-not $found.ContainsKey($name)) { throw "Missing classified manifest: $name" } }
    return $classes
}

function New-EuiPackage([string]$Source, [string]$Staging, [string]$Target) {
    $Source = Assert-EuiPath $Source; $Staging = Assert-EuiPath $Staging
    Assert-EuiTree $Source
    if ($Staging.StartsWith($Source + '\', [StringComparison]::OrdinalIgnoreCase) -or $Source.StartsWith($Staging + '\', [StringComparison]::OrdinalIgnoreCase) -or $Source -ieq $Staging) { throw 'Source and staging must be disjoint.' }
    if (-not (Test-Path -LiteralPath $Staging -PathType Container) -or @(Get-ChildItem -LiteralPath $Staging -Force).Count) { throw 'Staging must be an existing empty directory.' }
    $meta = ConvertFrom-EuiPkgmeta ([IO.File]::ReadAllText((Join-Path $Source '.pkgmeta')))
    if ($meta['package-as'] -cne 'EllesmereUI') { throw 'The installer requires the EllesmereUI core package name.' }
    $classes = Assert-EuiSnapshotTocs $Source $Target
    foreach ($folder in Get-ChildItem -LiteralPath $Source -Directory -Force | Where-Object { $_.Name -like 'EllesmereUI*' -and $_.Name -cne 'EllesmereUI' }) {
        $prefix = $folder.Name + '/'
        if (-not @($classes.Keys | Where-Object { $_.StartsWith($prefix) -and $_.Substring($prefix.Length).IndexOf('/') -lt 0 -and $classes[$_] -ne 'embedded' }).Count) { throw "Incomplete addon directory: $($folder.Name)" }
    }
    $moves = $meta['move-folders']; $destinations = @{}
    foreach ($src in $moves.Keys) {
        if (-not $src.StartsWith($meta['package-as'] + '/', [StringComparison]::Ordinal)) { throw "Move outside source package: $src" }
        $relative = $src.Substring($meta['package-as'].Length + 1)
        $dst = $moves[$src]; Assert-EuiName $dst
        if ($dst -ieq $meta['package-as'] -or $destinations.ContainsKey($dst)) { throw "Move destination collision: $dst" }
        foreach ($other in $moves.Keys) { if ($src -cne $other -and $src.StartsWith($other + '/')) { throw 'Overlapping folder moves.' } }
        $destinations[$dst] = $true
        if (-not (Test-Path -LiteralPath (Join-Path $Source $relative) -PathType Container)) { throw "Missing move source: $relative" }
        $moduleTocs = @($classes.Keys | Where-Object { $_.StartsWith($relative + '/') -and $_.Substring($relative.Length + 1).IndexOf('/') -lt 0 -and $classes[$_] -ne 'embedded' })
        if (-not $moduleTocs.Count) { throw "Move source has no classified addon manifest: $relative" }
    }
    foreach ($name in $classes.Keys) {
        if ($classes[$name] -eq 'embedded' -or (Test-EuiPackageIgnored $name $meta)) { continue }
        $mapped = Get-EuiPackageDestination $name $meta
        if ($mapped.Split('/').Count -ne 2) { throw "Addon requires a move-folders mapping: $name" }
    }
    foreach ($external in $meta.externals.Keys) {
        if (-not (Test-EuiPackageIgnored $external $meta) -and -not (Test-Path -LiteralPath (Join-Path $Source $external) -PathType Container)) { throw "Runtime external is not vendored: $external. No automatic download is permitted." }
    }
    # Exclude snapshot metadata and the historical duplicate core before copying.
    $excluded = @('.git','.github','.agents','.codex','.tools','.claude','.kiro','.release','.pkgmeta-cache')
    $xd = @('/XD') + $excluded + @((Join-Path $Source 'EllesmereUI'))
    $xf = @('/XF', (Join-Path $Source '.pkgmeta'), 'AGENTS.md')
    foreach ($rule in $meta.ignore) {
        $path = Join-Path $Source $rule
        if (Test-Path -LiteralPath $path -PathType Container) { $xd += $path }
        elseif (Test-Path -LiteralPath $path -PathType Leaf) { $xf += $path }
    }
    $core = Join-Path $Staging $meta['package-as']
    Invoke-Robocopy -Source $Source -Destination $core -ExtraArgs ($xd + $xf)
    foreach ($src in $moves.Keys) {
        $relative = $src.Substring($meta['package-as'].Length + 1)
        if (Test-EuiPackageIgnored $relative $meta) { continue }
        $from = Join-Path $Staging $src
        if (-not (Test-Path -LiteralPath $from -PathType Container)) { throw "Move source disappeared: $src" }
        Move-Item -LiteralPath $from -Destination (Join-Path $Staging $moves[$src]) -ErrorAction Stop
    }
    $null = Get-EuiPreparedFolders $Staging
    return $meta
}
