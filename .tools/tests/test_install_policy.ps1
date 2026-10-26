# Integration tests run exclusively inside a new temporary fixture directory.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../install/eui-package.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('eui-policy-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot
$script:passed = 0
function Assert($Condition, $Message = 'Assertion failed') { if (-not $Condition) { throw $Message } }
function Reject([scriptblock]$Action) { $failed = $false; try { & $Action | Out-Null } catch { $failed = $true }; Assert $failed 'Expected failure' }
function Put($Path, $Text = 'content') {
    $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($Path)) -Force
    [IO.File]::WriteAllText($Path, $Text)
}
function Fixture {
    $base = Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
    $script:dest = Join-Path $base 'AddOns'
    $script:stage = Join-Path $base 'stage'
    $script:work = Join-Path $base 'records'
    foreach ($path in @($dest, $stage, $work)) { $null = New-Item -ItemType Directory -Path $path -Force }
    Put (Join-Path $stage 'EllesmereUI/EllesmereUI.toc') 'main.lua'
    Put (Join-Path $stage 'EllesmereUI/main.lua') 'new'
    Put (Join-Path $dest 'EllesmereUI/EllesmereUI.toc') 'main.lua'
    Put (Join-Path $dest 'EllesmereUI/main.lua') 'old'
    Put (Join-Path $dest 'EllesmereUIOld/old.lua') 'old'
    $script:record = Get-EuiRecordPath $work $dest
    $script:failCopy = $false
    $script:failRollback = $false
}
function Record { Write-EuiInstallRecord $work $dest @('EllesmereUI', 'EllesmereUIOld') complete }
function Install {
    $script:warnings = @()
    Invoke-EuiInstallTransaction $work $dest $stage -WarningVariable script:warnings -WarningAction SilentlyContinue
}
function Invoke-Robocopy($Source, $Destination) {
    $null = New-Item -ItemType Directory -Path $Destination -Force
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
    if ($script:failCopy) {
        if ($script:failRollback) { Put (Join-Path $Destination 'blocker') 'prevent rollback'; $script:held = [IO.File]::Open((Join-Path $Destination 'blocker'), 'Open', 'Read', 'None') }
        throw 'Injected copy failure'
    }
}
function Check($Name, [scriptblock]$Action) {
    Fixture
    & $Action
    $script:passed++
    Write-Host "PASS: $Name"
}
$realReplace = (Get-Command Invoke-EuiManifestReplace).ScriptBlock
try {
    Check 'First install preserves unknown old directories silently' {
        Install
        Assert (Test-Path (Join-Path $dest 'EllesmereUIOld'))
        Assert ($warnings.Count -eq 0)
        Assert ((Get-EuiManifest $work $dest).Count -eq 1)
    }
    Check 'Legacy record cannot remove obsolete modules' {
        Record
        $json = [IO.File]::ReadAllText($record) | ConvertFrom-Json
        $json.Version = 1
        $json.PSObject.Properties.Remove('Fingerprints')
        [IO.File]::WriteAllText($record, ($json | ConvertTo-Json))
        Assert (@(Get-EuiRepairFolders $work $dest).Count -eq 2)
        Install
        Assert (Test-Path (Join-Path $dest 'EllesmereUIOld'))
    }
    Check 'Intact obsolete module removed without preservation warning' {
        Record; Install
        Assert (-not (Test-Path (Join-Path $dest 'EllesmereUIOld')))
        Assert ($warnings.Count -eq 0)
    }
    foreach ($change in @('add', 'delete', 'modify', 'rename', 'directory')) {
        Check "Obsolete module preserved after $change" {
            Record
            switch ($change) {
                add { Put (Join-Path $dest 'EllesmereUIOld/extra') }
                delete { Remove-Item -LiteralPath (Join-Path $dest 'EllesmereUIOld/old.lua') }
                modify { Put (Join-Path $dest 'EllesmereUIOld/old.lua') 'modified' }
                rename { Rename-Item -LiteralPath (Join-Path $dest 'EllesmereUIOld/old.lua') -NewName renamed.lua }
                directory { $null = New-Item -ItemType Directory -Path (Join-Path $dest 'EllesmereUIOld/empty') }
            }
            $before = Get-EuiFingerprint (Join-Path $dest 'EllesmereUIOld')
            Install
            Assert ((Get-EuiFingerprint (Join-Path $dest 'EllesmereUIOld')) -ceq $before)
            Assert ($warnings.Count -eq 1)
            Assert ("$warnings" -match 'Modified obsolete managed addons.*EllesmereUIOld')
            Assert (-not (Get-EuiManifest $work $dest).ContainsKey('EllesmereUIOld'))
        }
    }
    Check 'Independent plugins and unknown prefixed folders preserved silently' {
        Record
        Put (Join-Path $dest 'EllesmereUI_AddonSkins/custom.lua') 'plugin'
        Put (Join-Path $dest 'EllesmereUIUnknown/custom.lua') 'unknown'
        Install
        Assert (Test-Path (Join-Path $dest 'EllesmereUI_AddonSkins/custom.lua'))
        Assert (Test-Path (Join-Path $dest 'EllesmereUIUnknown/custom.lua'))
        Assert ($warnings.Count -eq 0)
    }
    Check 'Modified current module is replaced normally' {
        Record; Put (Join-Path $dest 'EllesmereUI/extra') 'user'
        Install
        Assert (-not (Test-Path (Join-Path $dest 'EllesmereUI/extra')))
        Assert ([IO.File]::ReadAllText((Join-Path $dest 'EllesmereUI/main.lua')) -eq 'new')
    }
    foreach ($kind in @('corrupt', 'incomplete', 'destination', 'duplicate', 'extraFingerprint')) {
        Check "Invalid manifest cannot delete modules: $kind" {
            Record
            $json = [IO.File]::ReadAllText($record) | ConvertFrom-Json
            switch ($kind) {
                corrupt { [IO.File]::WriteAllText($record, '{broken') }
                incomplete { $json.Fingerprints.PSObject.Properties.Remove('EllesmereUIOld') }
                destination { $json.Destination = $stage }
                duplicate { $json.Names += 'ELLESMEREUI' }
                extraFingerprint { $json.Fingerprints | Add-Member NoteProperty extra ('A' * 64) }
            }
            if ($kind -ne 'corrupt') { [IO.File]::WriteAllText($record, ($json | ConvertTo-Json)) }
            Install
            Assert (Test-Path (Join-Path $dest 'EllesmereUIOld'))
            Assert ($warnings.Count -gt 0)
        }
    }
    Check 'Copy failure restores replaced and removed modules and previous manifest' {
        Record
        $before = [IO.File]::ReadAllText($record)
        $script:failCopy = $true
        Reject { Install }
        Assert ([IO.File]::ReadAllText($record) -ceq $before)
        Assert ([IO.File]::ReadAllText((Join-Path $dest 'EllesmereUI/main.lua')) -eq 'old')
        Assert (Test-Path (Join-Path $dest 'EllesmereUIOld/old.lua'))
        Assert (-not (Test-Path "$record.pending"))
        $script:failCopy = $false
        Install
        Assert (-not (Test-Path (Join-Path $dest 'EllesmereUIOld')))
    }
    Check 'Manifest replacement failure rolls back modules and retains old record' {
        Record; $before = [IO.File]::ReadAllText($record)
        function Invoke-EuiManifestReplace { throw 'Injected replace failure' }
        Reject { Install }
        Assert ([IO.File]::ReadAllText($record) -ceq $before)
        Assert (Test-Path (Join-Path $dest 'EllesmereUIOld/old.lua'))
        Assert ([IO.File]::ReadAllText((Join-Path $dest 'EllesmereUI/main.lua')) -eq 'old')
        Assert (@(Get-ChildItem $work -Filter '*.tmp').Count -eq 0)
    }
    Check 'First manifest write failure rolls back without creating a record' {
        function Write-EuiInstallRecord { throw 'Injected first write failure' }
        Reject { Install }
        Assert (-not (Test-Path $record))
        Assert ([IO.File]::ReadAllText((Join-Path $dest 'EllesmereUI/main.lua')) -eq 'old')
    }
    Check 'Real File.Replace uses unique valid backup and cleans up on success' {
        Record
        Write-EuiInstallRecord $work $dest @('EllesmereUI') complete
        Assert ((Get-EuiManifest $work $dest).Count -eq 1)
        Assert (@(Get-ChildItem $work -Filter '*.previous').Count -eq 0)
        Reject { & $realReplace $record $record $null }
    }
    Check 'Independent Retail PTR and Experimental records' {
        Record
        $other = Join-Path ([IO.Path]::GetDirectoryName($dest)) '_xptr_'
        $null = New-Item -ItemType Directory -Path $other
        Assert ((Get-EuiRecordPath $work $other) -ne $record)
        Assert ((Get-EuiManifest $work $other).Count -eq 0)
        Assert ((Get-EuiRecordPath $work $dest.ToLowerInvariant()) -eq $record)
    }
    Check 'Repair accepts valid new record without requiring identical contents' {
        Record
        Put (Join-Path $dest 'EllesmereUI/main.lua') "line`n"
        Assert (@(Get-EuiRepairFolders $work $dest).Count -eq 2)
        Assert (@(Get-EuiRepairFolders $work (Join-Path $dest 'EllesmereUI')).Count -eq 1)
        $json = [IO.File]::ReadAllText($record) | ConvertFrom-Json
        $json.Fingerprints.PSObject.Properties.Remove('EllesmereUIOld')
        [IO.File]::WriteAllText($record, ($json | ConvertTo-Json))
        Reject { Get-EuiRepairFolders $work $dest -WarningAction SilentlyContinue }
    }
    Check 'Pending interrupted transaction blocks retry and repair without data loss' {
        Record
        Put "$record.pending" 'recovery information'
        Reject { Install }
        Reject { Get-EuiRepairFolders $work $dest }
        Assert (Test-Path (Join-Path $dest 'EllesmereUIOld/old.lua'))
        Assert ([IO.File]::ReadAllText("$record.pending") -eq 'recovery information')
    }
    Check 'Invalid paths traversal reserved names and overlapping roots rejected' {
        foreach ($name in @('..', '../outside', 'bad:name', 'NUL', 'x.')) { Reject { Get-EuiChildPath $dest $name } }
        Reject { Assert-EuiPath 'relative/path' }
        Reject { Invoke-EuiInstallTransaction $work $dest $dest }
    }
    Check 'Junctions cannot authorize traversal deletion or replacement' {
        $outside = Join-Path ([IO.Path]::GetDirectoryName($dest)) 'outside'
        $null = New-Item -ItemType Directory -Path $outside
        Put (Join-Path $outside 'keep') 'safe'
        $link = Join-Path $dest 'EllesmereUILink'
        $null = New-Item -ItemType Junction -Path $link -Target $outside
        Reject { Get-EuiFingerprint $link }
        Reject { Get-EuiInstallPlan $dest @('EllesmereUILink') $work }
        Assert ([IO.File]::ReadAllText((Join-Path $outside 'keep')) -eq 'safe')
        [IO.Directory]::Delete($link)
    }
    Check 'Concurrent transaction lock prevents any changes' {
        Record
        $lock = [IO.File]::Open("$record.lock", 'OpenOrCreate', 'ReadWrite', 'None')
        try { Reject { Install } } finally { $lock.Dispose() }
        Assert (Test-Path (Join-Path $dest 'EllesmereUIOld/old.lua'))
    }
    Check 'Fingerprint deterministic across enumeration and includes empty directories' {
        $folder = Join-Path $dest 'EllesmereUIOld'
        $before = Get-EuiFingerprint $folder
        Assert ((Get-EuiFingerprint $folder) -ceq $before)
        $null = New-Item -ItemType Directory -Path (Join-Path $folder empty)
        Assert ((Get-EuiFingerprint $folder) -cne $before)
    }
    Check 'Rollback failure retains backup and blocks retry until recovery' {
        Record
        $script:failCopy = $true
        $script:failRollback = $true
        try { Reject { Install } } finally { $script:held.Dispose() }
        Assert (Test-Path "$record.pending")
        $journal = [IO.File]::ReadAllText("$record.pending") | ConvertFrom-Json
        Assert (Test-Path (Join-Path $journal.Backup 'EllesmereUIOld/old.lua'))
        Assert ($journal.PreviousNames -contains 'EllesmereUIOld')
        $script:failCopy = $false
        Reject { Install }
        # Simulate the documented manual recovery using the retained journal.
        Assert-EuiTree (Join-Path $dest 'EllesmereUI')
        Remove-Item -LiteralPath (Join-Path $dest 'EllesmereUI') -Recurse -Force
        foreach ($name in $journal.PreviousNames) {
            [IO.Directory]::Move((Get-EuiChildPath $journal.Backup $name), (Get-EuiChildPath $dest $name))
        }
        Remove-Item -LiteralPath "$record.pending"
        Install
        Assert (-not (Test-Path (Join-Path $dest 'EllesmereUIOld')))
    }
    Check 'File.Replace partial failure restores manifest from valid backup' {
        Record; $before = [IO.File]::ReadAllText($record)
        function Invoke-EuiManifestReplace($Source, $Destination, $Backup) {
            [IO.File]::Copy($Destination, $Backup)
            [IO.File]::WriteAllText($Destination, 'injected partial replacement')
            throw 'Injected failure after backup creation'
        }
        Reject { Install }
        Assert ([IO.File]::ReadAllText($record) -ceq $before)
        Assert (Test-Path (Join-Path $dest 'EllesmereUIOld/old.lua'))
        Assert (@(Get-ChildItem $work -Filter '*.previous').Count -eq 0)
    }
    Check 'Manual and Codex installer functions use real ZIP staging copy and records' {
        $file = Join-Path $PSScriptRoot '../install/atualizar-eui.ps1'
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
        Assert ($errors.Count -eq 0)
        foreach ($statement in $ast.EndBlock.Statements) {
            if ($statement -is [Management.Automation.Language.FunctionDefinitionAst] -or
                ($statement -is [Management.Automation.Language.AssignmentStatementAst] -and
                 $statement.Left.Extent.Text -in @('$ignoredFiles', '$ignoredFolders', '$textExtensions', '$RepoOwner', '$RepoName'))) {
                . ([scriptblock]::Create($statement.Extent.Text))
            }
        }
        function New-Object {
            param([Parameter(Position=0)][string]$TypeName, [Parameter(Position=1)][object[]]$ArgumentList)
            if ($TypeName -eq 'System.Net.WebClient') {
                $client = [pscustomobject]@{}
                $client | Add-Member ScriptMethod DownloadFile {
                    param($Url, $Path)
                    $script:urls += $Url
                    [IO.File]::Copy($script:fixtureZip, $Path, $true)
                }
                $client | Add-Member ScriptMethod Dispose {}
                return $client
            }
            Microsoft.PowerShell.Utility\New-Object @PSBoundParameters
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archiveRoot = Join-Path $testRoot ('archive-' + [guid]::NewGuid().ToString('N'))
        Put (Join-Path $archiveRoot 'EllesmereUI-test/EllesmereUI.toc') "## Interface: 120105, 16001`nmain.lua`n"
        Put (Join-Path $archiveRoot 'EllesmereUI-test/.pkgmeta') "package-as: EllesmereUI`n"
        Put (Join-Path $archiveRoot 'EllesmereUI-test/.tools/toc_policy.json') @'
{"schema":1,"targets":{"new-features":"120105","12.1.7-PTR-features":"120105"},"camelot_interface":"16001","classes":{"retail":{"reason":"Fixture","paths":[]},"camelot":{"reason":"Fixture","paths":[]},"shared":{"reason":"Fixture","paths":["EllesmereUI.toc"]},"embedded":{"reason":"Fixture","paths":[]}}}
'@
        Put (Join-Path $archiveRoot 'EllesmereUI-test/main.lua') "new`n"
        Put (Join-Path $archiveRoot 'EllesmereUI-test/AGENTS.md') 'excluded'
        Put (Join-Path $archiveRoot 'EllesmereUI-test/.agents/secret') 'excluded'
        $script:fixtureZip = "$archiveRoot.zip"
        [IO.Compression.ZipFile]::CreateFromDirectory($archiveRoot, $script:fixtureZip)
        $WorkFolder = $work
        $RecordFolder = $work
        $script:urls = @()
        foreach ($client in @('Retail', 'PTR', 'Experimental')) {
            $target = Join-Path ([IO.Path]::GetDirectoryName($dest)) $client
            $null = New-Item -ItemType Directory -Path $target
            Put (Join-Path $target 'EllesmereUI_AddonSkins/plugin.lua') 'plugin'
            $branch = 'new-features'
            if ($client -ne 'Retail') { $branch = '12.1.7-PTR-features' }
            $output = Install-EUI $client $branch @($target) *>&1 | Out-String
            Assert ($output -match 'completed successfully')
            Assert ($output -notmatch 'preserved')
            Assert ([IO.File]::ReadAllText((Join-Path $target 'EllesmereUI/main.lua')) -ceq "new`r`n")
            Assert (-not (Test-Path (Join-Path $target 'EllesmereUI/AGENTS.md')))
            Assert (-not (Test-Path (Join-Path $target 'EllesmereUI/.agents')))
            Assert (@(Get-EuiRepairFolders $work $target).Count -eq 1)
        }
        Assert ($urls[0].EndsWith('/new-features.zip'))
        Assert ($urls[1].EndsWith('/12.1.7-PTR-features.zip'))
        function Read-Host { $answer = $script:answers[0]; $script:answers = @($script:answers | Select-Object -Skip 1); return $answer }
        function Test-Path { param([string]$LiteralPath); return $true }
        function Get-ChildItem { param([string]$LiteralPath) }
        foreach ($choice in @('1', '2', 'C')) {
            $script:answers = @('', 'invalid', $choice)
            $selected = Select-PtrAddOnsPath -WarningAction SilentlyContinue
            if ($choice -eq '1') { Assert ($selected -like '*\_ptr_\*') }
            elseif ($choice -eq '2') { Assert ($selected -like '*\_xptr_\*') }
            else { Assert ($null -eq $selected) }
            Assert ($script:answers.Count -eq 0)
        }
    }
    Check 'Manifest recovery failure retains pending marker and recovery backup' {
        Record
        function Invoke-EuiManifestReplace($Source, $Destination, $Backup) {
            [IO.File]::Copy($Destination, $Backup)
            [IO.File]::Delete($Destination)
            $null = New-Item -ItemType Directory -Path $Destination
            throw 'Injected manifest and restoration failure'
        }
        Reject { Install }
        Assert (Test-Path "$record.pending")
        $journal = [IO.File]::ReadAllText("$record.pending") | ConvertFrom-Json
        Assert (Test-Path ([IO.File]::ReadAllText("$record.pending.recovery")))
        Assert ($journal.PreviousNames -contains 'EllesmereUIOld')
        Assert (Test-Path (Join-Path $dest 'EllesmereUIOld/old.lua'))
        Reject { Install }
    }
    Check 'Actual repair uses shared destination lock and preserves functional conversion' {
        Record
        $file = Join-Path $PSScriptRoot '../install/corrigir-fim-de-linha.ps1'
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
        Assert ($errors.Count -eq 0)
        foreach ($statement in $ast.EndBlock.Statements) {
            if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) {
                . ([scriptblock]::Create($statement.Extent.Text))
            }
        }
        $WorkFolder = $work
        $textExtensions = @('.lua', '.toc')
        Put (Join-Path $dest 'EllesmereUI/main.lua') "line`n"
        $lock = [IO.File]::Open("$record.lock", 'OpenOrCreate', 'ReadWrite', 'None')
        try { Reject { Convert-LFtoCRLF $dest } } finally { $lock.Dispose() }
        Assert ([IO.File]::ReadAllText((Join-Path $dest 'EllesmereUI/main.lua')) -ceq "line`n")
        Convert-LFtoCRLF $dest
        Assert ([IO.File]::ReadAllText((Join-Path $dest 'EllesmereUI/main.lua')) -ceq "line`r`n")
    }
    Check 'Consecutive successful updates clean only their own backups' {
        Record
        Put (Join-Path $dest '.eui-backup-existing/keep') 'independent recovery'
        Put (Join-Path $work 'old.previous') 'old recovery'
        Install; Install; Install
        Assert (@(Get-ChildItem $dest -Directory -Filter '.eui-backup-*').Count -eq 1)
        Assert ([IO.File]::ReadAllText((Join-Path $dest '.eui-backup-existing/keep')) -eq 'independent recovery')
        Assert ([IO.File]::ReadAllText((Join-Path $work 'old.previous')) -eq 'old recovery')
        Assert (@(Get-ChildItem $work -Filter '*.previous').Count -eq 1)
    }
    Check 'Complete rollback removes the owned folder and manifest backups' {
        Record
        $script:failCopy = $true
        Reject { Install }
        Assert (@(Get-ChildItem $dest -Directory -Filter '.eui-backup-*').Count -eq 0)
        Assert (@(Get-ChildItem $work -Filter '*.previous').Count -eq 0)
        Assert (-not (Test-Path "$record.pending"))
    }
    Check 'Backup exists with original modules before new files are copied' {
        Record
        function Invoke-Robocopy($Source, $Destination) {
            $backups = @(Get-ChildItem $dest -Directory -Filter '.eui-backup-*')
            Assert ($backups.Count -eq 1)
            Assert ([IO.File]::ReadAllText((Join-Path $backups[0].FullName 'EllesmereUI/main.lua')) -eq 'old')
            Assert (Test-Path (Join-Path $backups[0].FullName 'EllesmereUIOld/old.lua'))
            $null = New-Item -ItemType Directory -Path $Destination -Force
            Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
        }
        Install
        Assert (@(Get-ChildItem $dest -Directory -Filter '.eui-backup-*').Count -eq 0)
    }
    foreach ($outcome in @('success', 'rollback')) {
        Check "Cleanup failure after $outcome reports warning without losing restored data" {
            Record
            function Remove-EuiTransactionBackup { throw 'Injected backup cleanup failure' }
            $script:failCopy = $outcome -eq 'rollback'
            if ($outcome -eq 'rollback') { Reject { Install } } else { Install }
            Assert (@(Get-ChildItem $dest -Directory -Filter '.eui-backup-*').Count -eq 1)
            Assert (-not (Test-Path "$record.pending"))
            Assert ("$warnings" -match 'Backup cleanup failed; retained')
            $expected = 'new'
            if ($outcome -eq 'rollback') { $expected = 'old' }
            Assert ([IO.File]::ReadAllText((Join-Path $dest 'EllesmereUI/main.lua')) -eq $expected)
        }
    }
    Check 'Manifest backup cleanup failure is an operational warning after successful publication' {
        Record
        function Remove-EuiManifestBackup { throw 'Injected manifest backup cleanup failure' }
        Install
        Assert ("$warnings" -match 'Previous manifest cleanup failed')
        Assert ((Get-EuiManifest $work $dest).Count -eq 1)
        Assert (-not (Test-Path "$record.pending"))
        Assert (@(Get-ChildItem $work -Filter '*.previous').Count -eq 1)
    }
    Check 'Fingerprint preflight failure never leaves an empty backup' {
        Record
        $realFingerprint = (Get-Command Get-EuiFingerprint).ScriptBlock
        function Get-EuiFingerprint($Root) {
            if ([IO.Path]::GetFileName($Root) -eq 'EllesmereUI') { throw 'Injected original fingerprint failure' }
            & $realFingerprint $Root
        }
        Reject { Install }
        Assert (@(Get-ChildItem $dest -Directory -Filter '.eui-backup-*').Count -eq 0)
        Assert ([IO.File]::ReadAllText((Join-Path $dest 'EllesmereUI/main.lua')) -eq 'old')
        Assert (-not (Test-Path "$record.pending"))
    }
    foreach ($outcome in @('success', 'rollback')) {
        Check "Marker cleanup failure after $outcome retains a valid backup reference" {
            Record
            function Remove-EuiTransactionMarker { throw 'Injected marker cleanup failure' }
            $script:failCopy = $outcome -eq 'rollback'
            if ($outcome -eq 'rollback') { Reject { Install } } else { Install }
            Assert (Test-Path "$record.pending")
            $journal = [IO.File]::ReadAllText("$record.pending") | ConvertFrom-Json
            Assert (Test-Path $journal.Backup)
            Assert ("$warnings" -match 'completed, but transaction marker cleanup failed')
            Assert ("$warnings" -match 'recovery is not incomplete')
            Reject { Install }
        }
    }
    Write-Host "Passed $passed integration tests on PowerShell $($PSVersionTable.PSVersion)."
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if (-not $resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path' }
    Assert-EuiTree $resolved
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
