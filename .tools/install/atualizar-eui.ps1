# atualizar-eui.ps1
# Downloads the latest EllesmereUI ZIP straight from GitHub, extracts it,
# arranges it into the structure WoW expects, removes the old EllesmereUI
# package folders from AddOns and copies the new ones in their place.
#
# Retail and PTR now use DIFFERENT branches and DIFFERENT folders:
#   Retail -> branch new-features   -> _retail_\Interface\AddOns
#   PTR    -> branch 12.1.7-PTR-features -> selected _ptr_ or _xptr_ AddOns folder
#
# Because of that, in "Both" mode the script downloads and installs the two
# branches in sequence (it is no longer a single shared download, as before).
#
# Tuned for speed:
#  - Downloads with the PowerShell progress bar off (it makes
#    Invoke-WebRequest MUCH slower than it needs to be).
#  - Copies done with multi-threaded robocopy instead of Copy-Item.
#
# MUST RUN AS ADMINISTRATOR (the Program Files folder is protected).
#
# Default usage (updates both, each from its own branch/folder):
#   .\atualizar-eui.ps1
#
# Or, to update only one of them:
#   .\atualizar-eui.ps1 -Only Retail
#   .\atualizar-eui.ps1 -Only PTR

param(
    [ValidateSet("Retail", "PTR", "Both")]
    [string]$Only = "Both",

    [string]$WorkFolder = "C:\Users\jonat\Desktop\EUI",

    [string]$RecordFolder = $WorkFolder,

    [string]$RetailBranch = "new-features",
    [string]$PtrBranch    = "12.1.7-PTR-features",

    [string]$RetailAddOnsPath = "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns"
)

$ErrorActionPreference = "Stop"

# Turn the PowerShell progress bar off: Invoke-WebRequest and Expand-Archive
# get MUCH faster without it (sometimes 10x+).
$ProgressPreference = "SilentlyContinue"

. (Join-Path $PSScriptRoot "eui-package.ps1")

$RepoOwner = "hellsy55"
$RepoName  = "EllesmereUI"

function Select-PtrAddOnsPath {
    $ptrPath = "C:\Program Files (x86)\World of Warcraft\_ptr_\Interface\AddOns"
    $experimentalPath = "C:\Program Files (x86)\World of Warcraft\_xptr_\Interface\AddOns"

    :selectionLoop while ($true) {
        Write-Host ""
        Write-Host "Option 1 - PTR"
        Write-Host "  $ptrPath"
        Write-Host "Option 2 - Experimental PTR"
        Write-Host "  $experimentalPath"
        Write-Host "C - Cancel without installing"
        $choice = (Read-Host "Choose 1 or 2, or C to cancel").Trim()
        switch ($choice) {
            "1" { $selectedPath = $ptrPath }
            "2" { $selectedPath = $experimentalPath }
            { $_ -in @("C", "Q", "0") } { return $null }
            default {
                Write-Warning "Invalid choice. Enter 1, 2, or C; there is no default."
                continue selectionLoop
            }
        }
        if (-not (Test-Path -LiteralPath $selectedPath -PathType Container)) {
            throw "Selected PTR AddOns directory does not exist: '$selectedPath'. No installation started."
        }
        try {
            Get-ChildItem -LiteralPath $selectedPath -ErrorAction Stop | Select-Object -First 1 | Out-Null
        } catch {
            throw "Cannot access selected PTR AddOns directory '$selectedPath': $_. No installation started."
        }
        return $selectedPath
    }
}

$PtrAddOnsPath = $null
if ($Only -eq "PTR" -or $Only -eq "Both") {
    $PtrAddOnsPath = Select-PtrAddOnsPath
    if (-not $PtrAddOnsPath) {
        Write-Host "Installation cancelled."
        return
    }
    Write-Host "Selected PTR AddOns directory: $PtrAddOnsPath"
}

# Check whether we are running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must run as Administrator. Close this window and reopen PowerShell with 'Run as administrator'."
    exit 1
}

$null = Assert-EuiPath $WorkFolder
if (-not (Test-Path -LiteralPath $WorkFolder)) {
    New-Item -ItemType Directory -Path $WorkFolder -Force | Out-Null
}

function Invoke-Robocopy {
    param(
        [string]$Source,
        [string]$Destination,
        [string[]]$ExtraArgs = @()
    )
    $args = @($Source, $Destination, "/E", "/MT:16", "/NFL", "/NDL", "/NJH", "/NJS", "/NC", "/NS") + $ExtraArgs
    & robocopy.exe @args | Out-Null
    # robocopy uses codes 0-7 for success, only >=8 is a real error
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy failed (code $LASTEXITCODE) copying from '$Source' to '$Destination'."
    }
}

# Text file extensions whose line endings should be normalized to CRLF
# before going into the AddOns folder (Lua, XML, TOC, etc. are plain text;
# images, fonts, sounds and so on are NOT in this list, to avoid corrupting
# binary files)
$textExtensions = @(".lua", ".xml", ".toc", ".txt", ".md", ".cfg", ".ini")

function Convert-LFtoCRLF {
    param([string]$Folder)

    # -Force includes hidden/system files, which sometimes come marked that
    # way inside the extracted ZIP (Get-ChildItem skips those by default)
    Assert-EuiTree $Folder
    $files = Get-ChildItem -LiteralPath $Folder -Recurse -File -Force | Where-Object {
        $textExtensions -contains $_.Extension.ToLower()
    }

    $converted = 0
    $failures = @()

    foreach ($file in $files) {
        try {
            # Files extracted from a ZIP sometimes come marked read-only,
            # which makes writing fail. Clear the attribute before trying
            # to write.
            if ($file.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
                Set-ItemProperty -LiteralPath $file.FullName -Name IsReadOnly -Value $false
            }

            # Detect a UTF-8 BOM so it can be preserved (or not) on rewrite
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $hasBOM = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF

            $content = [System.IO.File]::ReadAllText($file.FullName)
            # Literal .Replace() (not regex) - swap CRLF for LF first so the
            # CR is not duplicated, then swap every LF for CRLF
            $normalized = $content.Replace("`r`n", "`n").Replace("`n", "`r`n")
            if ($normalized -ne $content) {
                $encoding = New-Object System.Text.UTF8Encoding($hasBOM)
                [System.IO.File]::WriteAllText($file.FullName, $normalized, $encoding)
                $converted++
            }
        } catch {
            # Do not abort the whole conversion because of one bad file
            $failures += "$($file.FullName) -> $_"
        }
    }

    Write-Host "  $converted of $($files.Count) text file(s) converted to CRLF"
    if ($failures.Count -gt 0) {
        Write-Warning "  $($failures.Count) file(s) could NOT be converted:"
        $failures | ForEach-Object { Write-Warning "    $_" }
        throw "Line-ending conversion failed. See the file errors above."
    }
}

function Install-EUI {
    param(
        [string]$Name,
        [string]$Branch,
        [string[]]$AddOnsPaths
    )

    Write-Host ""
    Write-Host "=== Installing EllesmereUI ($Name) ===" -ForegroundColor Cyan
    Write-Host "Branch: $Branch"

    $swTotalName = [System.Diagnostics.Stopwatch]::StartNew()

    # Only install into AddOns folders that actually exist on this machine
    $validPaths = @($AddOnsPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
    $invalidPaths = @($AddOnsPaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Container) })
    foreach ($p in $invalidPaths) {
        Write-Warning "AddOns folder not found: $p -- skipping."
    }
    if ($validPaths.Count -eq 0) {
        Write-Warning "No valid AddOns folder for $Name -- skipping $Name."
        Write-Host ("  ($Name aborted after {0:N1}s)" -f $swTotalName.Elapsed.TotalSeconds)
        throw "No valid AddOns directory for $Name. Installation failed."
    }

    Assert-EuiName $Branch
    $null = Assert-EuiPath $WorkFolder
    $ZipUrl = "https://github.com/$RepoOwner/$RepoName/archive/refs/heads/$Branch.zip"
    $runId = [guid]::NewGuid().ToString("N")
    $zipPath = Join-Path $WorkFolder "EllesmereUI-$Branch-$runId.zip"
    $extractRoot = Join-Path $WorkFolder "_extracted_$Branch-$runId"
    $staging = $null
    $zipOwned = $false
    $extractOwned = $false
    $stagingOwned = $false
    try {

    $null = Assert-EuiPath $zipPath
    $zipReservation = [IO.File]::Open($zipPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $zipReservation.Dispose()
    $zipOwned = $true
    Write-Host "Downloading ZIP..."
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        # WebClient usually downloads faster than Invoke-WebRequest
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($ZipUrl, $zipPath)
        $webClient.Dispose()
    } catch {
        Write-Warning "Failed to download $ZipUrl -- skipping $Name. Error: $_"
        throw
    }
    Write-Host ("  Downloaded in {0:N1}s" -f $sw.Elapsed.TotalSeconds)

    Assert-EuiArchive $zipPath
    $null = Assert-EuiPath $extractRoot
    New-Item -ItemType Directory -Path $extractRoot -ErrorAction Stop | Out-Null
    $extractOwned = $true
    Assert-EuiTree $extractRoot

    Write-Host "Extracting ZIP..."
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force

    Assert-EuiTree $extractRoot
    $candidates = @(Get-ChildItem -LiteralPath $extractRoot -Directory | Where-Object { $_.Name -like "EllesmereUI-*" })
    if ($candidates.Count -ne 1) {
        Write-Warning "Did not find exactly one 'EllesmereUI-*' folder in $extractRoot -- skipping $Name."
        Write-Host ("  ($Name aborted after {0:N1}s)" -f $swTotalName.Elapsed.TotalSeconds)
        throw "Invalid extracted repository structure for $Name."
    }
    $ExtractedFolder = $candidates[0].FullName

    $staging = Join-Path $env:TEMP ("eui-staging-" + [guid]::NewGuid().ToString("N"))
    $null = Assert-EuiPath $staging
    New-Item -ItemType Directory -Path $staging -ErrorAction Stop | Out-Null
    $stagingOwned = $true
    $null = New-EuiPackage -Source $ExtractedFolder -Staging $staging -Target $Branch

    $preparedFolders = @(Get-EuiPreparedFolders $staging)
    $preparedNames = @($preparedFolders | ForEach-Object { $_.Name })
    $plans = @($validPaths | ForEach-Object { Get-EuiInstallPlan $_ $preparedNames $RecordFolder })

    Write-Host "Converting line endings (LF -> CRLF) in text files..."
    $swConv = [System.Diagnostics.Stopwatch]::StartNew()
    Convert-LFtoCRLF -Folder $staging
    Write-Host ("  Converted in {0:N1}s" -f $swConv.Elapsed.TotalSeconds)

    # From here on, the staging folder (downloaded/extracted/converted just
    # once) is copied into EACH valid AddOns folder received
    foreach ($plan in $plans) {
        $AddOnsPath = $plan.Root
        Write-Host "Destination ($Name): $AddOnsPath" -ForegroundColor Cyan
        Invoke-EuiInstallTransaction -WorkFolder $RecordFolder -AddOnsPath $AddOnsPath -Staging $staging
        Write-Host "OK: EllesmereUI ($Name) installed to: $AddOnsPath" -ForegroundColor Green
        Write-Host 'EUI installation completed successfully.' -ForegroundColor Green
    }

    } finally {
        $ownedDirectories = @()
        if ($stagingOwned) { $ownedDirectories += $staging }
        if ($extractOwned) { $ownedDirectories += $extractRoot }
        foreach ($temporaryDirectory in $ownedDirectories) {
            if ($temporaryDirectory -and (Test-Path -LiteralPath $temporaryDirectory)) {
                try {
                    Assert-EuiTree $temporaryDirectory
                    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction Stop
                } catch { Write-Warning "New distribution cleanup failed: '$temporaryDirectory'. $_" }
            }
        }
        if ($zipOwned -and (Test-Path -LiteralPath $zipPath)) {
            try { $null = Assert-EuiPath $zipPath; Remove-Item -LiteralPath $zipPath -Force -ErrorAction Stop }
            catch { Write-Warning "Downloaded ZIP cleanup failed: '$zipPath'. $_" }
        }
    }

    Write-Host ("=== $Name finished in {0:N1}s ===" -f $swTotalName.Elapsed.TotalSeconds) -ForegroundColor Cyan
}

$total = [System.Diagnostics.Stopwatch]::StartNew()
$installationFailed = $false

if ($Only -eq "Retail" -or $Only -eq "Both") {
    try {
        Install-EUI -Name "Retail" -Branch $RetailBranch -AddOnsPaths @($RetailAddOnsPath)
        Write-Host "Result (Retail): SUCCESS" -ForegroundColor Green
    } catch {
        $installationFailed = $true
        Write-Warning "Result (Retail): FAILED. $_"
    }
}

if ($Only -eq "PTR" -or $Only -eq "Both") {
    # Different branch from Retail, so it needs its own download/install
    # (the ZIP downloaded for Retail can no longer be reused)
    try {
        Install-EUI -Name "PTR" -Branch $PtrBranch -AddOnsPaths @($PtrAddOnsPath)
        Write-Host "Result (PTR): SUCCESS" -ForegroundColor Green
    } catch {
        $installationFailed = $true
        Write-Warning "Result (PTR): FAILED. $_"
    }
}

Write-Host ""
if ($installationFailed) {
    Write-Warning ("Installation failed for at least one requested destination after {0:N1}s." -f $total.Elapsed.TotalSeconds)
    exit 1
}
Write-Host ("=== Finished in {0:N1}s ===" -f $total.Elapsed.TotalSeconds) -ForegroundColor Green
exit 0
