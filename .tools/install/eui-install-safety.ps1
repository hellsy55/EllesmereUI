# Shared safety checks for installation and subsequent line-ending repair (PowerShell 5.1).
function Assert-EuiName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -in @('.', '..') -or
        $Name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
        $Name -ne $Name.TrimEnd(' ', '.') -or
        $Name -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|\.)') {
        throw "Unsafe Windows file name: '$Name'."
    }
}

function Assert-EuiPath {
    param([string]$Path)
    if ($Path -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\/]+[\\/][^\\/]+(?:[\\/]|$))' -or
        $Path -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Unsafe absolute path: '$Path'."
    }
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -ne [IO.Path]::GetPathRoot($full)) { $full = $full.TrimEnd('\') }
    $current = $full
    while ($current) {
        $item = $null
        try { $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop }
        catch [System.Management.Automation.ItemNotFoundException] {}
        if ($item) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse points are not allowed in an operated path: '$current'."
            }
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
    return $full
}

function Get-EuiChildPath {
    param([string]$Root, [string]$Name)
    Assert-EuiName $Name
    $rootFull = Assert-EuiPath $Root
    $child = [IO.Path]::GetFullPath((Join-Path $rootFull $Name))
    if (-not [string]::Equals([IO.Path]::GetDirectoryName($child), $rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is not an immediate child of '$rootFull': '$child'."
    }
    return $child
}

function Assert-EuiTree {
    param([string]$Root)
    $null = Assert-EuiPath $Root
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Directory missing: '$Root'." }
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($Root)
    while ($pending.Count) {
        $folder = $pending.Pop()
        $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($item in @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop)) {
            Assert-EuiName $item.Name
            if (-not $names.Add($item.Name)) { throw "Windows name collision in '$folder': '$($item.Name)'." }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point in operated tree: '$($item.FullName)'." }
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
        }
    }
}

function Assert-EuiArchive {
    param([string]$ZipPath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $paths = New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([StringComparer]::OrdinalIgnoreCase)
        $explicit = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $spelling = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
        $roots = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $archive.Entries) {
            $entryPath = $entry.FullName.Replace('\', '/')
            $parts = $entryPath.TrimEnd('/').Split('/')
            foreach ($part in $parts) { Assert-EuiName $part }
            $null = $roots.Add($parts[0])
            $mode = ($entry.ExternalAttributes -shr 16) -band 0xF000
            if ($mode -eq 0xA000 -or ($entry.ExternalAttributes -band 0x400)) { throw "Link entry in ZIP: '$entryPath'." }
            $key = $parts -join '/'
            if (-not $explicit.Add($key)) { throw "Duplicate Windows path in ZIP: '$entryPath'." }
            for ($i = 0; $i -lt $parts.Count; $i++) {
                $prefix = $parts[0..$i] -join '/'
                if ($spelling.ContainsKey($prefix) -and -not [string]::Equals($spelling[$prefix], $prefix, [StringComparison]::Ordinal)) {
                    throw "Windows case collision in ZIP: '$prefix'."
                }
                $spelling[$prefix] = $prefix
                $isDirectory = $i -lt ($parts.Count - 1) -or $entryPath.EndsWith('/')
                if ($paths.ContainsKey($prefix) -and $paths[$prefix] -ne $isDirectory) { throw "File/directory collision in ZIP: '$prefix'." }
                $paths[$prefix] = $isDirectory
            }
        }
        if ($roots.Count -ne 1 -or @($roots)[0] -notlike 'EllesmereUI-*') { throw 'ZIP must contain exactly one EllesmereUI repository root.' }
    } finally { $archive.Dispose() }
}

function Get-EuiPreparedFolders {
    param([string]$Staging)
    Assert-EuiTree $Staging
    $folders = @(Get-ChildItem -LiteralPath $Staging -Force -Directory | Sort-Object Name)
    if (-not $folders.Count -or -not (Test-Path -LiteralPath (Join-Path $Staging 'EllesmereUI\EllesmereUI.toc') -PathType Leaf)) {
        throw 'Prepared package is empty or missing the core EllesmereUI.toc.'
    }
    if (@(Get-ChildItem -LiteralPath $Staging -Force -File).Count) { throw 'Unexpected loose file in prepared package.' }
    foreach ($folder in $folders) {
        $tocs = @(Get-ChildItem -LiteralPath $folder.FullName -File -Force | Where-Object { $_.Extension -eq '.toc' })
        if (-not $tocs.Count) { throw "Prepared addon has no TOC: '$($folder.Name)'." }
        foreach ($toc in $tocs) {
            $references = 0
            foreach ($line in [IO.File]::ReadAllLines($toc.FullName)) {
                $reference = ($line -replace '\s+\[.*\]\s*$', '').Trim()
                if (-not $reference -or $reference.StartsWith('#')) { continue }
                $parts = $reference.Replace('/', '\').Split('\')
                foreach ($part in $parts) { Assert-EuiName $part }
                $file = Join-Path $folder.FullName $reference
                if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Incomplete addon '$($folder.Name)': missing '$reference'." }
                $references++
            }
            if (-not $references) { throw "Empty addon TOC: '$($toc.FullName)'." }
        }
    }
    return $folders
}

function Get-EuiInstallPlan {
    param([string]$AddOnsPath, [string[]]$Names, [string]$WorkFolder)
    $root = Assert-EuiPath $AddOnsPath
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "AddOns directory missing: '$root'." }
    $authorized = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $Names) {
        $null = Get-EuiChildPath $root $name
        if (-not $authorized.Add($name)) { throw "Duplicate addon name: '$name'." }
    }
    if (-not $authorized.Count) { throw 'No addon names authorized for installation.' }
    $previous = @{}
    if ($WorkFolder) { $previous = Get-EuiManifest $WorkFolder $root }
    $removed = @()
    $existing = @(Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop)
    $existingNames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $replaced = @()
    $preserved = @()
    foreach ($item in $existing) {
        if (-not $existingNames.Add($item.Name)) { throw "Windows name collision in AddOns: '$($item.Name)'." }
        if ($authorized.Contains($item.Name)) {
            if (-not $item.PSIsContainer) { throw "Addon destination is a file: '$($item.FullName)'." }
            Assert-EuiTree $item.FullName
            $replaced += $item
        } elseif ($previous.ContainsKey($item.Name)) {
            if (-not $item.PSIsContainer) { throw "Managed addon is now a file: '$($item.FullName)'." }
            $fingerprint = Get-EuiFingerprint $item.FullName
            if ($fingerprint -ceq $previous[$item.Name]) { $removed += $item }
            else { $preserved += $item.Name }
        }
    }
    return [pscustomobject]@{ Root = $root; Replaced = $replaced; Removed = $removed; Expected = $previous; Preserved = @($preserved | Sort-Object) }
}

function Write-EuiPreservedWarning {
    param([string[]]$Names, [switch]$Completed)
    if (-not $Names.Count) { return }
    Write-Warning ("Modified obsolete managed addons were preserved and are no longer managed: " + ($Names -join ', '))
}

function Get-EuiRecordPath {
    param([string]$WorkFolder, [string]$AddOnsPath)
    $root = Assert-EuiPath $AddOnsPath
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $id = ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToUpperInvariant())))).Replace('-', '') }
    finally { $hash.Dispose() }
    return Get-EuiChildPath $WorkFolder "_installed_eui_$id.json"
}

function Write-EuiInstallRecord {
    param([string]$WorkFolder, [string]$AddOnsPath, [string[]]$Names, [string]$Status)
    $path = Get-EuiRecordPath $WorkFolder $AddOnsPath
    $null = Assert-EuiPath $path
    if ($Status -cne 'complete') { throw 'Only successful installations may publish a manifest.' }
    $fingerprints = @{}
    foreach ($name in $Names) {
        $fingerprints[$name] = Get-EuiFingerprint (Get-EuiChildPath $AddOnsPath $name)
    }
    $record = @{ Version = 2; Destination = (Assert-EuiPath $AddOnsPath); Names = @($Names); Status = $Status; Fingerprints = $fingerprints }
    $temporary = "$path.$([guid]::NewGuid().ToString('N')).tmp"
    $previous = "$temporary.previous"
    $null = Assert-EuiPath $temporary
    $null = Assert-EuiPath $previous
    $previousDisposable = $false
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($record | ConvertTo-Json -Depth 5))
        $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
        finally { $stream.Dispose() }
        if (Test-Path -LiteralPath $path) {
            Invoke-EuiManifestReplace $temporary $path $previous
            $previousDisposable = $true
        } else {
            [IO.File]::Move($temporary, $path)
        }
    } catch {
        # File.Replace can create its backup before reporting a failure.
        if (Test-Path -LiteralPath $previous) {
            try {
                [IO.File]::Copy($previous, $path, $true)
                if ((Get-FileHash -LiteralPath $previous -Algorithm SHA256).Hash -cne
                    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash) { throw 'Restored manifest verification failed.' }
                $previousDisposable = $true
            }
            catch {
                $errorObject = New-Object IO.IOException "Manifest recovery failed; retain '$previous' for recovery. $_"
                $errorObject.Data['EuiManifestRecoveryBackup'] = $previous
                throw $errorObject
            }
        }
        throw
    } finally {
        if ($previousDisposable -and (Test-Path -LiteralPath $previous)) {
            try { Remove-EuiManifestBackup $previous }
            catch { Write-Warning "Previous manifest cleanup failed; retained '$previous'. $_" }
        }
        if (Test-Path -LiteralPath $temporary) {
            try { Remove-Item -LiteralPath $temporary -Force -ErrorAction Stop }
            catch { Write-Warning "Manifest temporary file cleanup failed: '$temporary'. $_" }
        }
    }
}

function Remove-EuiManifestBackup {
    param([string]$Path)
    $null = Assert-EuiPath $Path
    Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
}

function Invoke-EuiManifestReplace {
    param([string]$Source, [string]$Destination, [string]$Backup)
    foreach ($path in @($Source, $Destination, $Backup)) { $null = Assert-EuiPath $path }
    if (Test-Path -LiteralPath $Backup) { throw "Manifest backup already exists: '$Backup'." }
    [IO.File]::Replace($Source, $Destination, $Backup)
}

function Get-EuiRepairFolders {
    param([string]$WorkFolder, [string]$TargetFolder)
    $root = Assert-EuiPath $TargetFolder
    $recordPath = Get-EuiRecordPath $WorkFolder $root
    $single = $null
    if (-not (Test-Path -LiteralPath $recordPath -PathType Leaf)) {
        $single = [IO.Path]::GetFileName($root)
        $root = [IO.Path]::GetDirectoryName($root)
        $recordPath = Get-EuiRecordPath $WorkFolder $root
    }
    $null = Assert-EuiPath $recordPath
    if (-not (Test-Path -LiteralPath $recordPath -PathType Leaf)) { throw 'No successful installation record found. Install EUI successfully before repairing line endings.' }
    if ((Test-Path -LiteralPath "$recordPath.pending") -or (Test-Path -LiteralPath "$recordPath.pending.recovery") -or (Test-Path -LiteralPath "$recordPath.incomplete")) { throw 'Unfinished EUI transaction requires recovery before line-ending repair.' }
    $json = [IO.File]::ReadAllText($recordPath)
    if (-not $json.TrimStart().StartsWith('{')) { throw 'Installation record must be a JSON object. No correction started.' }
    $record = $json | ConvertFrom-Json
    if ($record -isnot [pscustomobject] -or
        ($record.Version -isnot [int] -and $record.Version -isnot [long]) -or $record.Version -notin @(1, 2) -or
        $record.Status -isnot [string] -or $record.Status -cne 'complete' -or
        $record.Destination -isnot [string] -or
        -not [string]::Equals($record.Destination, $root, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Invalid or incomplete EUI installation record. No correction started.'
    }
    if ($record.Names -isnot [array] -or $record.Names.Count -eq 0) { throw 'Installation record names must be a nonempty array. No correction started.' }
    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $record.Names) {
        if ($name -isnot [string] -or [string]::IsNullOrWhiteSpace($name)) { throw 'Installation record names must be nonempty strings. No correction started.' }
        Assert-EuiName $name
        if (-not $name.StartsWith('EllesmereUI', [StringComparison]::OrdinalIgnoreCase) -or -not $names.Add($name)) {
            throw "Invalid or duplicate installation record name: '$name'. No correction started."
        }
    }
    if (-not $names.Contains('EllesmereUI')) { throw 'Installation record is missing the core EllesmereUI addon. No correction started.' }
    if ($record.Version -eq 2 -and (Get-EuiManifest $WorkFolder $root).Count -ne $names.Count) {
        throw 'Invalid fingerprint manifest. No correction started.'
    }
    $plan = Get-EuiInstallPlan $root @($record.Names)
    if ($plan.Replaced.Count -ne @($record.Names).Count) { throw 'An installed addon is missing. No correction started.' }
    if ($single) {
        $folders = @($plan.Replaced | Where-Object { $_.Name -eq $single })
        if ($folders.Count -ne 1) { throw "Folder is not part of the installed package: '$single'." }
        return $folders
    }
    return $plan.Replaced
}

function Get-EuiFingerprint {
    param([string]$Root)
    Assert-EuiTree $Root
    $rootFull = (Assert-EuiPath $Root).TrimEnd('\')
    $entries = New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in @(Get-ChildItem -LiteralPath $rootFull -Recurse -Force -ErrorAction Stop)) {
        $relative = $item.FullName.Substring($rootFull.Length + 1).Replace('\', '/')
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($relative))
        if ($item.PSIsContainer) { $entries.Add("D:$encoded") }
        else {
            $digest = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
            $entries.Add("F:${encoded}:$digest")
        }
    }
    $entries.Sort([StringComparer]::Ordinal)
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes(($entries -join "`n"))))).Replace('-', '')
    } finally { $hash.Dispose() }
}

function Get-EuiManifest {
    # Invalid or legacy records never authorize obsolete-folder removal.
    param([string]$WorkFolder, [string]$AddOnsPath)
    $path = Get-EuiRecordPath $WorkFolder $AddOnsPath
    $null = Assert-EuiPath $path
    if (-not (Test-Path -LiteralPath $path)) { return @{} }
    try {
        $record = [IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop
        if ($record.Version -eq 1) { return @{} }
        if ($record -isnot [pscustomobject] -or ($record.Version -isnot [int] -and $record.Version -isnot [long]) -or $record.Version -ne 2 -or
            $record.Status -isnot [string] -or $record.Status -cne 'complete' -or $record.Destination -isnot [string] -or
            -not [string]::Equals($record.Destination, (Assert-EuiPath $AddOnsPath), [StringComparison]::OrdinalIgnoreCase) -or
            $record.Names -isnot [array] -or -not $record.Names.Count -or
            $record.Fingerprints -isnot [pscustomobject]) { throw 'Unsupported, incomplete or wrong-destination manifest.' }
        $result = @{}
        foreach ($name in $record.Names) {
            if ($name -isnot [string]) { throw 'Invalid manifest name.' }
            Assert-EuiName $name
            if (-not $name.StartsWith('EllesmereUI', [StringComparison]::OrdinalIgnoreCase) -or $result.ContainsKey($name)) { throw 'Invalid or duplicate manifest name.' }
            $value = $record.Fingerprints.PSObject.Properties[$name].Value
            if ($value -isnot [string] -or $value -cnotmatch '^[0-9A-F]{64}$') { throw 'Invalid manifest fingerprint.' }
            $result[$name] = $value
        }
        if (-not $result.ContainsKey('EllesmereUI') -or @($record.Fingerprints.PSObject.Properties).Count -ne $result.Count) { throw 'Incomplete manifest.' }
        return $result
    } catch { Write-Warning "Installation manifest cannot authorize cleanup; obsolete folders will be preserved. $_"; return @{} }
}

function Invoke-EuiInstallTransactionCore {
    [CmdletBinding()]
    param([string]$WorkFolder, [string]$AddOnsPath, [string]$Staging)
    $folders = @(Get-EuiPreparedFolders $Staging)
    $names = @($folders | ForEach-Object { $_.Name })
    $plan = Get-EuiInstallPlan $AddOnsPath $names $WorkFolder
    $recordPath = Get-EuiRecordPath $WorkFolder $plan.Root
    $null = Assert-EuiPath $recordPath
    $pendingPath = "$recordPath.pending"
    $null = Assert-EuiPath $pendingPath
    if ((Test-Path -LiteralPath "$recordPath.incomplete")) { throw "Earlier incomplete installation found: inspect '$recordPath.incomplete' before installing. Preserve its diagnostic data." }
    if ((Test-Path -LiteralPath $pendingPath) -or (Test-Path -LiteralPath "$pendingPath.recovery")) { throw "Unfinished EUI transaction: inspect '$pendingPath' and recover its backup before retrying." }
    $original = @{}
    foreach ($folder in @($plan.Replaced) + @($plan.Removed)) {
        $original[$folder.Name] = Get-EuiFingerprint $folder.FullName
    }
    $backup = Get-EuiChildPath $plan.Root ('.eui-backup-' + [guid]::NewGuid().ToString('N'))
    $null = Assert-EuiPath $backup
    New-Item -ItemType Directory -Path $backup -ErrorAction Stop | Out-Null
    $moved = @()
    $recovered = $false
    $journalOwned = $false
    $created = @()
    $complete = $false
    $markerCleanupFailed = $false
    try {
        $journal = @{ Destination = $plan.Root; Backup = $backup; Names = $names; PreviousNames = @(@($plan.Replaced) + @($plan.Removed) | ForEach-Object { $_.Name }); Manifest = $recordPath }
        $stream = [IO.File]::Open($pendingPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $journalOwned = $true
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes(($journal | ConvertTo-Json))
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally { $stream.Dispose() }
        foreach ($folder in @($plan.Replaced) + @($plan.Removed)) {
            $source = Get-EuiChildPath $plan.Root $folder.Name
            Assert-EuiTree $source
            [IO.Directory]::Move($source, (Get-EuiChildPath $backup $folder.Name))
            $moved += $folder.Name
            if ($plan.Removed -contains $folder) {
                $savedFolder = Get-EuiChildPath $backup $folder.Name
                if ((Get-EuiFingerprint $savedFolder) -cne $plan.Expected[$folder.Name]) {
                    [IO.Directory]::Move($savedFolder, $source)
                    $moved = @($moved | Where-Object { $_ -ne $folder.Name })
                    $plan.Preserved += $folder.Name
                }
            }
        }
        foreach ($folder in $folders) {
            $destination = Get-EuiChildPath $plan.Root $folder.Name
            $null = Assert-EuiPath $destination
            if (Test-Path -LiteralPath $destination) { throw "Destination appeared during installation: '$destination'." }
            $created += $folder.Name
            Invoke-Robocopy -Source $folder.FullName -Destination $destination
            if ((Get-EuiFingerprint $destination) -cne (Get-EuiFingerprint $folder.FullName)) {
                throw "Installed content verification failed: '$destination'."
            }
        }
        Write-EuiInstallRecord $WorkFolder $plan.Root $names 'complete'
        $complete = $true
    } catch {
        $failure = $_
        try {
            foreach ($name in $created) {
                $destination = Get-EuiChildPath $plan.Root $name
                if (Test-Path -LiteralPath $destination) {
                    Assert-EuiTree $destination
                    Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction Stop
                }
            }
            foreach ($name in $moved) {
                $source = Get-EuiChildPath $backup $name
                Assert-EuiTree $source
                [IO.Directory]::Move($source, (Get-EuiChildPath $plan.Root $name))
            }
        } catch { throw "Installation failed: $failure. Rollback failed: $_. Recovery backup retained at '$backup'." }
        foreach ($name in $moved) {
            $restored = Get-EuiChildPath $plan.Root $name
            if ((Get-EuiFingerprint $restored) -cne $original[$name]) {
                throw "Rollback verification failed for '$restored'. Retain '$pendingPath' and '$backup' for recovery. Original failure: $failure"
            }
        }
        $manifestBackup = $failure.Exception.Data['EuiManifestRecoveryBackup']
        if ($manifestBackup) {
            try {
                $recoveryPath = "$pendingPath.recovery"
                $null = Assert-EuiPath $recoveryPath
                $info = [Text.Encoding]::UTF8.GetBytes($manifestBackup)
                $recoveryStream = [IO.File]::Open($recoveryPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $recoveryStream.Write($info, 0, $info.Length); $recoveryStream.Flush($true) }
                finally { $recoveryStream.Dispose() }
            } catch { Write-Warning "Cannot append manifest recovery information to '$pendingPath'. Backup: '$manifestBackup'. $_" }
            Write-Warning "Folders restored but manifest recovery is incomplete. Retain '$pendingPath' and '$manifestBackup'."
        } else { $recovered = $true }
        throw $failure
    } finally {
        if ($journalOwned -and ($complete -or $recovered)) {
            try { Remove-EuiTransactionMarker $pendingPath }
            catch {
                $markerCleanupFailed = $true
                $outcome = 'Installation'
                if ($recovered) { $outcome = 'Rollback' }
                Write-Warning "$outcome completed, but transaction marker cleanup failed: '$pendingPath'. Backup retained at '$backup' to keep its recovery reference valid. Inspect the completed state before removing the marker and this backup; recovery is not incomplete. $_"
            }
        }
        if (-not $markerCleanupFailed -and ($complete -or $recovered -or -not @(Get-ChildItem -LiteralPath $backup -Force).Count)) {
            try {
                Remove-EuiTransactionBackup $backup
            } catch { Write-Warning "Backup cleanup failed; retained '$backup': $_" }
        }
    }
    Write-EuiPreservedWarning -Names $plan.Preserved -Completed
}

function Remove-EuiTransactionMarker {
    param([string]$Path)
    $null = Assert-EuiPath $Path
    Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
}

function Remove-EuiTransactionBackup {
    param([string]$Path)
    Assert-EuiTree $Path
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
}

function Invoke-EuiInstallTransaction {
    [CmdletBinding()]
    param([string]$WorkFolder, [string]$AddOnsPath, [string]$Staging)
    $root = Assert-EuiPath $AddOnsPath
    $stage = Assert-EuiPath $Staging
    $work = Assert-EuiPath $WorkFolder
    foreach ($other in @($stage, $work)) {
        if ($other.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
            $other.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -or
            $root.StartsWith($other + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'AddOns, staging and record storage must not overlap.'
        }
    }
    $lockPath = (Get-EuiRecordPath $work $root) + '.lock'
    $null = Assert-EuiPath $lockPath
    # Keep a stable lock inode: deleting it after release permits lock races.
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try { Invoke-EuiInstallTransactionCore $work $root $stage }
    finally { $lock.Dispose() }
}
