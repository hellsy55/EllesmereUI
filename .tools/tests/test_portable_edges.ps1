# Exercise portable control flow using disposable destinations and simulated HTTP only.
param([Parameter(Mandatory=$true)][string]$RetailDirectory, [Parameter(Mandatory=$true)][string]$PtrDirectory)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '../install/eui-package.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('eui-portable-edges-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot
$script:passed = 0
function Assert($Value, $Message) { if (-not $Value) { throw $Message } }
function Reject([scriptblock]$Action) {
    $failed = $false; try { & $Action | Out-Null } catch { $failed = $true }
    Assert $failed 'Expected rejection'
}
function Put($Path, $Text) {
    $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($Path)) -Force
    [IO.File]::WriteAllText($Path, $Text)
}
function Parse($Path) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    Assert (-not $errors.Count) "PowerShell syntax: $Path"
    return $ast
}
function New-Snapshot($Source, $Archive, $RootName) {
    $zip = [IO.Compression.ZipFile]::Open($Archive, 'Create')
    try {
        foreach ($file in Get-ChildItem -LiteralPath $Source -Recurse -File -Force) {
            $relative = $file.FullName.Substring($Source.Length + 1).Replace('\','/')
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, ($RootName + '/' + $relative))
        }
    } finally { $zip.Dispose() }
}
function New-TestRequest($Url) {
    $script:requests += $Url
    $request = [pscustomobject]@{ Method=''; UserAgent=''; Accept=''; Timeout=0; ReadWriteTimeout=0; AllowAutoRedirect=$false; MaximumAutomaticRedirections=0; KeepAlive=$false; Url=$Url }
    $request | Add-Member ScriptMethod Abort {}
    $request | Add-Member ScriptMethod GetResponse {
        if ($script:httpApi -and $this.Url -notlike '*api.github.com*') { throw 'Injected primary source failure' }
        $response = [pscustomobject]@{ StatusCode=200; ContentLength=([IO.FileInfo]$script:downloadFixture).Length }
        $response | Add-Member ScriptMethod Close {}
        $response | Add-Member ScriptMethod GetResponseStream { return [IO.File]::OpenRead($script:downloadFixture) }
        return $response
    }
    return $request
}
$probeImplementation = (Get-Command Invoke-EuiWriteProbe).ScriptBlock
try {
    foreach ($client in 'Retail','PTR','XPTR') {
        & {
            $directory = if ($client -eq 'Retail') { $RetailDirectory } else { $PtrDirectory }
            $target = if ($client -eq 'Retail') { 'new-features' } else { '12.1.7-PTR-features' }
            $scriptName = if ($client -eq 'Retail') { 'Install-EUI-Retail.ps1' } else { 'Install-EUI-PTR.ps1' }
            $ast = Parse (Join-Path $directory $scriptName)
            foreach ($statement in $ast.EndBlock.Statements) {
                if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) {
                    $code = $statement.Extent.Text.Replace('[Net.HttpWebRequest]::Create($url)', '(New-TestRequest $url)')
                    . ([scriptblock]::Create($code))
                }
            }
            $transaction = (Get-Command Install-Prepared).ScriptBlock
            function Install-Prepared($Stage, $AddOns) {
                $script:events += 'transaction'
                Assert ($script:events -contains 'probe') 'Transaction preceded write probe'
                return & $transaction $Stage $AddOns
            }
            function Invoke-EuiWriteProbe($AddOns) {
                $script:events += 'probe'
                Assert (Test-Path (Join-Path $stage 'EllesmereUI/EllesmereUI.toc')) 'Probe preceded payload validation'
                Assert (-not (Test-Path (Join-Path $stage 'EllesmereUILoadoutManager'))) 'Held module reached probe'
                if ($script:denyProbe) { throw [UnauthorizedAccessException]::new('Injected permission denial') }
                & $probeImplementation $AddOns
            }
            function Start-Process { throw 'Simulated elevation unavailable; no real UAC is executed' }
            function Resolve-Retail($Selected) { return $Selected }
            function Resolve-AnyPTRAddOns($Selected) { return $Selected }
            function Test-RetailGameRunning { return $false }
            function Test-SelectedClientGameRunning { return $false }
            function Invoke-WebRequest {
                param($Uri, $OutFile, [switch]$UseBasicParsing)
                $script:requests += $Uri
                if ($script:downloadFails) { throw 'Injected download failure' }
                [IO.File]::Copy($script:downloadFixture, $OutFile)
            }
            $main = @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] })
            Assert ($main.Count -eq 1) 'Unexpected portable main'
            # Keep real control flow, replacing process exits so each case can assert its outcome.
            $mainCode = $main[0].Extent.Text.Replace('exit 1', 'throw').Replace('exit 0', 'return')
            $source = Join-Path $testRoot "$client-source"
            $interface = if ($client -eq 'Retail') { '120105' } else { '120107' }
            $tocPaths = @('EllesmereUI.toc','EllesmereUINew/EllesmereUINew.toc','EllesmereUILoadoutManager/EllesmereUILoadoutManager.toc','EllesmereUISimpleLootCouncil/EllesmereUISimpleLootCouncil.toc')
            $policy = @{ schema=1; targets=@{'new-features'='120105';'12.1.7-PTR-features'='120107'}; camelot_interface='16001'; classes=@{
                shared=@{reason='Fixture';paths=$tocPaths}; retail=@{reason='Fixture';paths=@()}; camelot=@{reason='Fixture';paths=@()}; embedded=@{reason='Fixture';paths=@('EllesmereUINew/vendor/Library.toc')}
            } }
            Put (Join-Path $source '.tools/toc_policy.json') ($policy | ConvertTo-Json -Depth 12)
            $meta = "package-as: EllesmereUI`nmove-folders:`n  EllesmereUI/EllesmereUINew: EllesmereUINew`nignore:`n  - EllesmereUILoadoutManager`n  - EllesmereUISimpleLootCouncil`n"
            Put (Join-Path $source '.pkgmeta') $meta
            foreach ($toc in $tocPaths) {
                Put (Join-Path $source $toc) "## Interface: $interface, 16001`nmain.lua`n"
                Put (Join-Path (Split-Path (Join-Path $source $toc)) 'main.lua') '-- fixture'
            }
            Put (Join-Path $source 'EllesmereUINew/vendor/Library.toc') "## Interface: 1`nvendor.lua`n"
            Put (Join-Path $source 'EllesmereUINew/vendor/vendor.lua') '-- embedded fixture'
            foreach ($api in $false,$true) {
                $rootName = if ($api) { 'hellsy55-EllesmereUI-0123456789' } else { "EllesmereUI-$target" }
                $archive = Join-Path $testRoot "$client-$api.zip"
                New-Snapshot $source $archive $rootName
                foreach ($failure in 'none','download','validation','probe') {
                    & {
                        $caseRoot = Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
                        $AddOnsPath = Join-Path $caseRoot 'AddOns'
                        Put (Join-Path $AddOnsPath 'Independent/keep.lua') '-- keep'
                        $before = Get-EuiFingerprint $AddOnsPath
                        $configDir = Join-Path $caseRoot 'records'; $configFile = Join-Path $configDir 'settings.json'
                        $StateFolder=$configDir; $ChooseFolder=$false; $PrepareOnly=$false; $ArchivePath=$null; $ReportPath=$null
                        $script:events=@(); $script:requests=@(); $script:httpApi=$api
                        $script:downloadFixture=$archive; $script:downloadFails=$failure -eq 'download'; $script:denyProbe=$failure -eq 'probe'
                        if ($failure -eq 'download' -and $client -ne 'Retail') { function Download-PTRArchive { throw 'Injected download failure' } }
                        if ($failure -eq 'validation') {
                            $invalid = Join-Path $caseRoot 'invalid.zip'
                            Put (Join-Path $source '.pkgmeta') 'unsupported: yes'
                            New-Snapshot $source $invalid $rootName
                            Put (Join-Path $source '.pkgmeta') $meta
                            $script:downloadFixture=$invalid
                        }
                        if ($failure -eq 'none') {
                            . ([scriptblock]::Create($mainCode)) | Out-Null
                            Assert (($script:events -join ',') -eq 'probe,transaction') 'Wrong probe/transaction order'
                            Assert (Test-Path (Join-Path $AddOnsPath 'EllesmereUINew/vendor/Library.toc')) 'Arbitrary embedded library missing'
                            foreach ($held in 'EllesmereUILoadoutManager','EllesmereUISimpleLootCouncil') { Assert (-not (Test-Path (Join-Path $AddOnsPath $held))) 'Held module distributed' }
                            Assert ((Get-Content (Join-Path $AddOnsPath 'Independent/keep.lua') -Raw) -eq '-- keep') 'Independent addon changed'
                        } else {
                            Reject { . ([scriptblock]::Create($mainCode)) }
                            Assert ($script:events -notcontains 'transaction') 'Failure started a transaction'
                            if ($failure -ne 'probe') { Assert ($script:events -notcontains 'probe') 'Failure reached write probe' }
                            Assert ((Get-EuiFingerprint $AddOnsPath) -eq $before) 'Failure modified AddOns'
                        }
                        Assert (@(Get-ChildItem -LiteralPath $AddOnsPath -Filter 'EUI-write-test-*').Count -eq 0) 'Probe leaked temporary directory'
                        Assert (-not $work -or -not (Test-Path -LiteralPath $work)) 'Portable work directory leaked'
                        $script:passed++; Write-Host "PASS: $client API=$api failure=$failure"
                    }
                }
                # Execute the exporter's retry/stream-copy function with only HTTP transport simulated.
                $exportAst = Parse (Join-Path $directory 'Export-InstallableZIP.ps1')
                $download = @($exportAst.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'Download-GithubArchive' })[0]
                $downloadCode = $download.Extent.Text.Replace('[Net.HttpWebRequest]::Create($urls[$attempt])', '(New-TestRequest $urls[$attempt])')
                . ([scriptblock]::Create($downloadCode))
                $script:httpApi=$api; $script:requests=@(); $script:downloadFixture=$archive
                $downloaded = Join-Path $testRoot "$client-$api-downloaded.zip"
                Download-GithubArchive hellsy55 EllesmereUI ('1' * 40) $downloaded
                Assert ((Get-FileHash $downloaded).Hash -eq (Get-FileHash $archive).Hash) 'Simulated download bytes differ'
                Assert ($script:requests.Count -eq $(if ($api) { 3 } else { 1 })) 'Fallback order changed'
                Assert ((Assert-EuiPortableArchive $downloaded $target) -ceq $rootName) 'Downloaded root not accepted'
                $script:passed++; Write-Host "PASS: $client exporter simulated source API=$api"
            }
        }
    }
    # Reject unapproved roots and preserve default repository archive behavior.
    $minimal = Join-Path $testRoot 'minimal'; Put (Join-Path $minimal 'EllesmereUI.toc') 'main.lua'
    foreach ($rootName in 'arbitrary','EllesmereUI-other-branch','other-EllesmereUI-0123456','hellsy55-EllesmereUI-not-a-sha') {
        $archive = Join-Path $testRoot ([guid]::NewGuid().ToString('N') + '.zip')
        New-Snapshot $minimal $archive $rootName
        Reject { Assert-EuiPortableArchive $archive new-features }
        $script:passed++
    }
    $apiArchive = Join-Path $testRoot 'api-default-rejection.zip'
    New-Snapshot $minimal $apiArchive 'hellsy55-EllesmereUI-0123456'
    Reject { Assert-EuiArchive $apiArchive }
    $script:passed++
    $approved = 'hellsy55-EllesmereUI-0123456'
    foreach ($case in 'traversal','multiple-roots','symlink','reparse','case-collision','duplicate','file-directory') {
        $archive = Join-Path $testRoot ([guid]::NewGuid().ToString('N') + '.zip')
        $zip = [IO.Compression.ZipFile]::Open($archive, 'Create')
        try {
            [void]$zip.CreateEntry("$approved/EllesmereUI.toc")
            switch ($case) {
                traversal { [void]$zip.CreateEntry("$approved/../escape") }
                multiple-roots { [void]$zip.CreateEntry('another-root/file') }
                symlink { $entry = $zip.CreateEntry("$approved/link"); $entry.ExternalAttributes = -1610612736 }
                reparse { $entry = $zip.CreateEntry("$approved/link"); $entry.ExternalAttributes = 0x400 }
                case-collision { [void]$zip.CreateEntry("$approved/A.lua"); [void]$zip.CreateEntry("$approved/a.lua") }
                duplicate { [void]$zip.CreateEntry("$approved/EllesmereUI.toc") }
                file-directory { [void]$zip.CreateEntry("$approved/file"); [void]$zip.CreateEntry("$approved/file/child") }
            }
        } finally { $zip.Dispose() }
        Reject { Assert-EuiPortableArchive $archive new-features }
        $script:passed++; Write-Host "PASS: API-root archive rejects $case"
    }
    $wrongExtracted = Join-Path $testRoot 'wrong-extracted'
    $null = New-Item -ItemType Directory -Path (Join-Path $wrongExtracted 'EllesmereUI-new-features') -Force
    Reject { Get-EuiPortableSource $wrongExtracted $approved }
    $script:passed++
    $shaArchive = Join-Path $testRoot 'sha-root.zip'
    New-Snapshot $minimal $shaArchive ('EllesmereUI-' + ('a' * 40))
    Assert ((Assert-EuiPortableArchive $shaArchive new-features) -ceq ('EllesmereUI-' + ('a' * 40))) 'Full commit root rejected'
    $script:passed++
    Write-Host "Passed $script:passed portable edge cases; no real network, UAC or WoW destination used."
} finally {
    Assert-EuiTree $testRoot
    if (-not $testRoot.StartsWith([IO.Path]::GetTempPath())) { throw 'Unsafe fixture cleanup' }
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
