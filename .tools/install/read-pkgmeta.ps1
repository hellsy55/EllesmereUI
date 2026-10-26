param([Parameter(Mandatory=$true)][string]$InputPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'eui-package.ps1')
$bundle = [IO.File]::ReadAllText($InputPath) | ConvertFrom-Json
$result = @{}
foreach ($item in $bundle.PSObject.Properties) { $result[$item.Name] = ConvertFrom-EuiPkgmeta $item.Value }
$result | ConvertTo-Json -Depth 20 -Compress
