# corrigir-fim-de-linha.ps1
# Fixes text files that ended up with LF line endings (they should be CRLF)
# inside the already-installed EllesmereUI folders.
#
# Default usage (fixes Retail and PTR, if they exist):
#   .\corrigir-fim-de-linha.ps1
#
# Or just one of them:
#   .\corrigir-fim-de-linha.ps1 -Only Retail
#   .\corrigir-fim-de-linha.ps1 -Only PTR
#
# Or pointing at a specific folder (ignores -Only):
#   .\corrigir-fim-de-linha.ps1 -Folder "C:\Any\Path"

param(
    [string]$Folder,

    [string]$WorkFolder = "C:\Users\jonat\Desktop\EUI",

    [ValidateSet("Retail", "PTR", "Both")]
    [string]$Only = "Both",

    [string]$RetailAddOnsPath = "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns",
    [string]$PtrAddOnsPath    = "C:\Program Files (x86)\World of Warcraft\_xptr_\Interface\AddOns"
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "eui-install-safety.ps1")

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must run as Administrator (the folders under Program Files are protected)."
    exit 1
}

$textExtensions = @(".lua", ".xml", ".toc", ".txt", ".md", ".cfg", ".ini")

function Convert-LFtoCRLFCore {
    param([string]$TargetFolder)

    if (-not (Test-Path -LiteralPath $TargetFolder)) {
        Write-Warning "Folder not found, skipping: $TargetFolder"
        return
    }

    $folders = @(Get-EuiRepairFolders $WorkFolder $TargetFolder)
    $files = @($folders | ForEach-Object {
        Assert-EuiTree $_.FullName
        Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force -ErrorAction Stop
    } | Where-Object { $textExtensions -contains $_.Extension.ToLower() })

    $converted = 0
    $alreadyOk = 0
    $failures = @()

    foreach ($file in $files) {
        try {
            # Clear "read-only" if set, otherwise the write fails
            if ($file.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
                Set-ItemProperty -LiteralPath $file.FullName -Name IsReadOnly -Value $false
            }

            # Detect a UTF-8 BOM so it can be preserved (or not) on rewrite
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $hasBOM = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF

            $content = [System.IO.File]::ReadAllText($file.FullName)
            $normalized = $content.Replace("`r`n", "`n").Replace("`n", "`r`n")

            if ($normalized -ne $content) {
                $encoding = New-Object System.Text.UTF8Encoding($hasBOM)
                [System.IO.File]::WriteAllText($file.FullName, $normalized, $encoding)
                $converted++
            } else {
                $alreadyOk++
            }
        } catch {
            $failures += "$($file.FullName) -> $_"
        }
    }

    Write-Host "  Folder: $TargetFolder"
    Write-Host "    $converted file(s) fixed | $alreadyOk already OK | $($files.Count) scanned"
    if ($failures.Count -gt 0) {
        Write-Warning "    $($failures.Count) file(s) could NOT be fixed:"
        $failures | ForEach-Object { Write-Warning "      $_" }
        throw "Line-ending correction failed. See the file errors above."
    }
}

function Convert-LFtoCRLF {
    param([string]$TargetFolder)
    if (-not (Test-Path -LiteralPath $TargetFolder)) {
        Write-Warning "Folder not found, skipping: $TargetFolder"
        return
    }
    $root = Assert-EuiPath $TargetFolder
    $record = Get-EuiRecordPath $WorkFolder $root
    if (-not (Test-Path -LiteralPath $record -PathType Leaf)) {
        $record = Get-EuiRecordPath $WorkFolder ([IO.Path]::GetDirectoryName($root))
    }
    $lockPath = "$record.lock"
    $null = Assert-EuiPath $lockPath
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try { Convert-LFtoCRLFCore $TargetFolder }
    finally { $lock.Dispose() }
}

Write-Host "=== Fixing line endings (LF -> CRLF) ===" -ForegroundColor Cyan

if ($Folder) {
    Convert-LFtoCRLF -TargetFolder $Folder
} else {
    if ($Only -eq "Retail" -or $Only -eq "Both") {
        Convert-LFtoCRLF -TargetFolder $RetailAddOnsPath
    }
    if ($Only -eq "PTR" -or $Only -eq "Both") {
        Convert-LFtoCRLF -TargetFolder $PtrAddOnsPath
    }
}

Write-Host ""
Write-Host "=== Finished ===" -ForegroundColor Green
