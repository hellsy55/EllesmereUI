# Packaging tests use synthetic snapshots only; no WoW destination is used.
param([string]$PortableRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../install/eui-package.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('eui-package-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot
$passed = 0
function Assert($Value, $Message = 'Assertion failed') { if (-not $Value) { throw $Message } }
function Put($Path, $Text) {
    $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($Path)) -Force
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}
function Fixture {
    $script:source = Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
    $script:stage = Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $stage
    $script:meta = @'
package-as: EllesmereUI
move-folders:
  EllesmereUI/EllesmereUINew: EllesmereUINew
  EllesmereUI/EllesmereUILoadoutManager: EllesmereUILoadoutManager
  EllesmereUI/EllesmereUISimpleLootCouncil: EllesmereUISimpleLootCouncil
externals:
  Libs/Runtime:
    url: https://example.invalid/library
enable-nolib-creation: no
ignore:
  - docs
  - unused.txt
  - EllesmereUILoadoutManager
  - EllesmereUISimpleLootCouncil
'@
    Put (Join-Path $source '.pkgmeta') $meta
    $script:policy = @{ schema = 1; targets = @{ 'new-features' = '120105'; '12.1.7-PTR-features' = '120107' }; camelot_interface = '16001'; classes = @{
        shared = @{ reason = 'Fixture'; paths = @('EllesmereUI.toc','EllesmereUINew/EllesmereUINew.toc','EllesmereUILoadoutManager/EllesmereUILoadoutManager.toc','EllesmereUISimpleLootCouncil/EllesmereUISimpleLootCouncil.toc') }
        retail = @{ reason = 'Fixture'; paths = @() }; camelot = @{ reason = 'Fixture'; paths = @() }
        embedded = @{ reason = 'Fixture'; paths = @('Libs/Runtime/vendor.toc') }
    } }
    Save-Policy
    foreach ($name in $policy.classes.shared.paths) {
        Put (Join-Path $source $name) "## Interface: 120105, 16001`nmain.lua`n"
        Put (Join-Path (Split-Path (Join-Path $source $name)) 'main.lua') "-- runtime`n"
    }
    Put (Join-Path $source 'Libs/Runtime/vendor.toc') "## Interface: 1`nvendor.lua`n"
    Put (Join-Path $source 'Libs/Runtime/vendor.lua') '-- vendor'
    Put (Join-Path $source 'EllesmereUI/main.lua') '-- stale duplicate core'
    Put (Join-Path $source 'docs/readme.txt') 'ignored'
    Put (Join-Path $source 'unused.txt') 'ignored'
    Put (Join-Path $source 'Media/texture.bin') 'binary'
}
function Save-Policy { Put (Join-Path $source '.tools/toc_policy.json') ($policy | ConvertTo-Json -Depth 10) }
function Prepare { $null = New-EuiPackage $source $stage new-features }
function Reject([scriptblock]$Action) {
    $failed = $false; try { & $Action | Out-Null } catch { $failed = $true }
    Assert $failed 'Expected rejection'
}
function Invoke-Robocopy {
    param($Source, $Destination, $ExtraArgs)
    & robocopy.exe $Source $Destination /E /MT:16 /R:0 /W:0 /NFL /NDL /NJH /NJS /NC /NS @ExtraArgs | Out-Null
    if ($LASTEXITCODE -ge 8) { throw 'Fixture robocopy failed' }
}
function Check($Name, [scriptblock]$Action) {
    Fixture; & $Action; $script:passed++; Write-Host "PASS: $Name"
}
try {
    Check 'Literal files/directories ignored; held modules excluded; dynamic move; core and libraries preserved' {
        Prepare
        foreach ($name in 'EllesmereUILoadoutManager','EllesmereUISimpleLootCouncil','EllesmereUI/docs','EllesmereUI/unused.txt','.tools','EllesmereUI/.pkgmeta') { Assert (-not (Test-Path (Join-Path $stage $name))) $name }
        Assert (Test-Path (Join-Path $stage 'EllesmereUINew/EllesmereUINew.toc'))
        Assert (Test-Path (Join-Path $stage 'EllesmereUI/Libs/Runtime/vendor.lua'))
        Assert ((Get-Content (Join-Path $stage 'EllesmereUI/main.lua') -Raw) -match 'runtime')
        Assert ((Get-FileHash (Join-Path $stage 'EllesmereUI/Media/texture.bin')).Hash -eq (Get-FileHash (Join-Path $source 'Media/texture.bin')).Hash)
    }
    Check 'Removing inherited exclusion distributes module' {
        Put (Join-Path $source '.pkgmeta') ($meta.Replace('  - EllesmereUILoadoutManager', ''))
        Prepare; Assert (Test-Path (Join-Path $stage 'EllesmereUILoadoutManager/EllesmereUILoadoutManager.toc'))
    }
    Check 'Adding exclusion hides only exact module and not a similarly named module' {
        Put (Join-Path $source '.pkgmeta') ($meta + "`n  - EllesmereUINe`n")
        Prepare; Assert (Test-Path (Join-Path $stage 'EllesmereUINew'))
    }
    Check 'New excluded module is absent' {
        Put (Join-Path $source '.pkgmeta') ($meta + "`n  - EllesmereUINew`n")
        Prepare; Assert (-not (Test-Path (Join-Path $stage 'EllesmereUINew')))
    }
    Check 'Unmapped module rejected before copying' {
        Put (Join-Path $source '.pkgmeta') ($meta.Replace('  EllesmereUI/EllesmereUINew: EllesmereUINew', ''))
        Reject { Prepare }; Assert (@(Get-ChildItem $stage -Force).Count -eq 0)
    }
    Check 'Unknown manifest even in excluded directory fails closed' {
        Put (Join-Path $source 'docs/unknown.toc') 'main.lua'; Reject { Prepare }
    }
    Check 'Incomplete new module without a manifest is rejected' {
        Put (Join-Path $source 'EllesmereUIIncomplete/main.lua') '-- incomplete'; Reject { Prepare }
    }
    Check 'Repository metadata is excluded inside custom modules too' {
        Put (Join-Path $source 'EllesmereUINew/.agents/private') 'metadata'
        Put (Join-Path $source 'EllesmereUINew/AGENTS.md') 'metadata'
        Prepare
        Assert (-not (Test-Path (Join-Path $stage 'EllesmereUINew/.agents')))
        Assert (-not (Test-Path (Join-Path $stage 'EllesmereUINew/AGENTS.md')))
    }
    Check 'UTF8 BOM and CRLF in pkgmeta are supported' {
        [IO.File]::WriteAllText((Join-Path $source '.pkgmeta'), $meta.Replace("`r`n","`n").Replace("`n","`r`n"), (New-Object Text.UTF8Encoding($true)))
        Prepare; Assert (Test-Path (Join-Path $stage 'EllesmereUINew'))
    }
    foreach ($bad in @('unknown-directive: yes', "ignore:`n  - ../escape", "ignore:`n  - EllesmereUI*", "ignore: [module]", "ignore:`n  - 'quoted'", "package-as: EllesmereUI`npackage-as: EllesmereUI")) {
        Check "Unsupported syntax rejected: $bad" { Put (Join-Path $source '.pkgmeta') $bad; Reject { Prepare }; Assert (@(Get-ChildItem $stage -Force).Count -eq 0) }
    }
    Check 'Runtime omitted by ignore rejected before destination installation' {
        Put (Join-Path $source '.pkgmeta') ($meta + "`n  - main.lua`n"); Reject { Prepare }
    }
    Check 'Missing runtime external rejected' {
        Remove-Item (Join-Path $source 'Libs/Runtime') -Recurse -Force
        $policy.classes.embedded.paths = @(); Save-Policy; Reject { Prepare }
    }
    Check 'Move collision rejected before copy' {
        Put (Join-Path $source '.pkgmeta') ($meta.Replace(': EllesmereUINew', ': EllesmereUI')); Reject { Prepare }
    }
    Check 'Missing move source rejected' {
        Put (Join-Path $source '.pkgmeta') ($meta.Replace('EllesmereUI/EllesmereUINew:', 'EllesmereUI/Missing:')); Reject { Prepare }
    }
    Check 'Published manifests are checked, never rewritten' {
        $toc = Join-Path $source 'EllesmereUI.toc'; Put $toc "## Interface: 999`nmain.lua`n"
        $hash = (Get-FileHash $toc).Hash; Reject { Prepare }; Assert ((Get-FileHash $toc).Hash -eq $hash)
    }
    Check 'PTR target comes exclusively from snapshot policy' {
        foreach ($name in $policy.classes.shared.paths) { Put (Join-Path $source $name) "## Interface: 120107, 16001`nmain.lua`n" }
        $null = New-EuiPackage $source $stage '12.1.7-PTR-features'
        Assert (Test-Path (Join-Path $stage 'EllesmereUINew'))
    }
    Check 'BOM CRLF and binary bytes preserved by shared preparation' {
        $file = Join-Path $source 'main.lua'; [IO.File]::WriteAllText($file, "-- utf8`r`n", (New-Object Text.UTF8Encoding($true)))
        Prepare; Assert ((Get-FileHash $file).Hash -eq (Get-FileHash (Join-Path $stage 'EllesmereUI/main.lua')).Hash)
    }
    Check 'Nonempty and overlapping staging rejected without changes' {
        Put (Join-Path $stage 'keep') 'keep'; Reject { Prepare }
        Reject { New-EuiPackage $source $source new-features }; Assert (Test-Path (Join-Path $stage 'keep'))
    }
    Write-Host "Passed $passed packaging tests."
} finally {
    Assert-EuiTree $testRoot
    if (-not $testRoot.StartsWith([IO.Path]::GetTempPath())) { throw 'Unsafe fixture cleanup' }
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
