# Offline equivalence checks. All destinations and records are disposable fixtures.
param(
    [Parameter(Mandatory=$true)][string]$RetailDirectory,
    [Parameter(Mandatory=$true)][string]$PtrDirectory,
    [Parameter(Mandatory=$true)][string]$RetailSnapshot,
    [Parameter(Mandatory=$true)][string]$PtrSnapshot,
    [Parameter(Mandatory=$true)][string]$RetailPrepared,
    [Parameter(Mandatory=$true)][string]$PtrPrepared
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../install/eui-package.ps1')
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('eui-portable-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixtureRoot
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Manifest([string]$Root) {
    $result = @{}
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Force) {
        $name = $file.FullName.Substring($Root.TrimEnd('\').Length + 1).Replace('\','/')
        $result[$name] = "$($file.Length):$((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash)"
    }
    return $result
}
function Equal-Payload($Expected, $Actual) {
    Assert ($Expected.Count -eq $Actual.Count) 'Payload file counts differ'
    foreach ($key in $Expected.Keys) { Assert ($Actual[$key] -ceq $Expected[$key]) "Payload differs: $key" }
}
try {
    foreach ($client in 'Retail','PTR') {
        & {
            $directory = if ($client -eq 'Retail') { $RetailDirectory } else { $PtrDirectory }
            $snapshot = if ($client -eq 'Retail') { $RetailSnapshot } else { $PtrSnapshot }
            $prepared = if ($client -eq 'Retail') { $RetailPrepared } else { $PtrPrepared }
            $target = if ($client -eq 'Retail') { 'new-features' } else { '12.1.7-PTR-features' }
            $script = Join-Path $directory $(if ($client -eq 'Retail') { 'Install-EUI-Retail.ps1' } else { 'Install-EUI-PTR.ps1' })
            foreach ($path in @($script, (Join-Path $directory 'Export-InstallableZIP.ps1'), (Join-Path $directory 'eui-package.ps1'), (Join-Path $directory 'eui-install-safety.ps1'))) {
                $tokens = $null; $errors = $null
                $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
                Assert (-not $errors.Count) "PowerShell syntax: $path"
                if ($path -eq $script -or $path.EndsWith('Export-InstallableZIP.ps1')) {
                    foreach ($statement in $ast.EndBlock.Statements) {
                        if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) { . ([scriptblock]::Create($statement.Extent.Text)) }
                    }
                }
            }
            # Reuse the repository entry point's existing normalization, without its install main.
            $tokens = $null; $errors = $null
            $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../install/atualizar-eui.ps1'), [ref]$tokens, [ref]$errors)
            foreach ($statement in $ast.EndBlock.Statements) {
                if ($statement -is [Management.Automation.Language.FunctionDefinitionAst] -and $statement.Name -in 'Invoke-Robocopy','Convert-LFtoCRLF') { . ([scriptblock]::Create($statement.Extent.Text)) }
            }
            $textExtensions = @('.lua','.xml','.toc','.txt','.md','.cfg','.ini')
            $stage = Join-Path $fixtureRoot "$client-source-prepared"
            $null = New-Item -ItemType Directory -Path $stage
            $null = New-EuiPackage $snapshot $stage $target
            Convert-LFtoCRLF $stage
            $expected = Manifest $stage
            Equal-Payload $expected (Manifest $prepared)
            foreach ($held in 'EllesmereUILoadoutManager','EllesmereUISimpleLootCouncil') { Assert (-not (Test-Path (Join-Path $stage $held))) "Excluded module present: $held" }
            $zip = Join-Path $fixtureRoot "$client.zip"
            New-PortableAddonZip $prepared $zip
            Assert-PortableAddonZip $zip $prepared $(if ($client -eq 'Retail') { 'RetailEUI' } else { 'PTREUI' })
            $exported = Join-Path $fixtureRoot "$client-exported"
            Expand-Archive -LiteralPath $zip -DestinationPath $exported
            Equal-Payload $expected (Manifest $exported)
            $configDir = Join-Path $fixtureRoot "$client-records"
            foreach ($destination in $(if ($client -eq 'PTR') { @('PTR','XPTR') } else { @('Retail') })) {
                $addons = Join-Path $fixtureRoot "$destination-AddOns"
                $null = New-Item -ItemType Directory -Path $addons
                $null = Install-Prepared $stage $addons
                Equal-Payload $expected (Manifest $addons)
            }
            Write-Host "PASS: $client shared preparation, PrepareOnly, export and fixture installation match ($($expected.Count) paths/sizes/SHA256)."
        }
    }
} finally {
    Assert-EuiTree $fixtureRoot
    if (-not $fixtureRoot.StartsWith([IO.Path]::GetTempPath())) { throw 'Unsafe cleanup path' }
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}
