"""Adapt the supplied portable installers without changing their transaction records."""
import argparse
from pathlib import Path, PurePosixPath
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def adapt(text, target):
    start = text.index("    $core = Join-Path $stage 'EllesmereUI'")
    end = text.index('    foreach ($file in Get-ChildItem -LiteralPath $stage', start)
    message = "    Write-Host 'Normalizing text files"
    if message in text[start:end]:
        end = text.index(message, start)
    text = text[:start] + ("    New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null\n"
                           f"    $null = New-EuiPackage -Source $source -Staging $stage -Target '{target}'\n") + text[end:]
    for old, new in [('Copy-Tree $Stage $staging', 'Copy-Tree $Stage $staging -Exact'),
                     ('Copy-Tree $stage $OutputPath', 'Copy-Tree $stage $OutputPath -Exact')]:
        if text.count(old) != 1:
            raise ValueError('Unexpected portable copy boundary: ' + old)
        text = text.replace(old, new)
    # PrepareOnly must not merge with a stale output or overwrite an existing directory.
    text = text.replace("    $work = Join-Path ([IO.Path]::GetTempPath())", """    if ($PrepareOnly -and (Test-Path -LiteralPath $OutputPath)) { throw 'PrepareOnly requires a new output directory.' }
    $work = Join-Path ([IO.Path]::GetTempPath())""", 1)
    insertion = """
. (Join-Path $PSScriptRoot 'eui-package.ps1')
function Invoke-Robocopy {
    param([string]$Source, [string]$Destination, [string[]]$ExtraArgs = @())
    & robocopy.exe $Source $Destination /E /MT:16 /R:2 /W:1 /NFL /NDL /NJH /NJS /NC /NS @ExtraArgs | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Package copy failed: $LASTEXITCODE" }
}
"""
    pos = text.index('$work = $null')
    text = text[:pos] + insertion + text[pos:]
    # Use the hardened archive validator before extraction, retaining the portable record format.
    text = text.replace('    Assert-ArchiveEntries $ArchivePath', '    Assert-EuiArchive $ArchivePath')
    return text


def exporter(text):
    needle = '        foreach ($file in Get-ChildItem -LiteralPath $Prepared -Recurse -File -Force) {'
    start = text.index(needle)
    end = text.index('    } finally {', start)
    text = text[:end] + """        $payloadFiles = @(Get-ChildItem -LiteralPath $Prepared -Recurse -File -Force)
        if (@($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') }).Count -ne $payloadFiles.Count) { throw 'Export file count differs from prepared payload.' }
        foreach ($file in $payloadFiles) {
            $relative = Get-ZipRelativePath -Root $Prepared -FullPath $file.FullName
            $entry = $zip.GetEntry($relative)
            if ($entry.Length -ne $file.Length) { throw "Export size differs: $relative" }
            $stream = $entry.Open(); $sha = [Security.Cryptography.SHA256]::Create()
            try { $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
            finally { $stream.Dispose(); $sha.Dispose() }
            if ($hash -cne (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) { throw "Export hash differs: $relative" }
        }
""" + text[end:]
    return text


def correct_portable(text, target):
    # This migration accepts both original adapters and our earlier generated bundle.
    approved_call = f"    $archiveRoot = Assert-EuiPortableArchive $ArchivePath '{target}'"
    if approved_call in text:
        if (text.count(approved_call) != 1 or text.count('Invoke-EuiWriteProbe $addons') != 1
                or text.index('Invoke-EuiWriteProbe $addons') < text.index('[void](Get-PreparedFolders $stage)')
                or '-ArchivePath \'$quotedArchive\'' not in text):
            raise ValueError('Unexpected corrected portable boundaries')
        return text
    archive_call = '    Assert-EuiArchive $ArchivePath'
    if text.count(archive_call) != 1:
        raise ValueError('Unexpected archive validation boundary')
    text = text.replace(archive_call, approved_call, 1)
    root_block = """    $roots = @(Get-ChildItem -LiteralPath $extracted -Directory)
    if ($roots.Count -ne 1) { throw 'Unexpected download structure.' }
    $source = $roots[0].FullName"""
    if text.count(root_block) != 1:
        raise ValueError('Unexpected extracted root boundary')
    text = text.replace(root_block, '    $source = Get-EuiPortableSource $extracted $archiveRoot', 1)
    start = text.index("        $probe = Join-Path $addons ")
    end = text.index('    } elseif (-not $ArchivePath', start)
    probe = text[start:end]
    expected = """        try {
            New-Item -ItemType Directory -Path $probe | Out-Null
            Remove-Item -LiteralPath $probe -Force
        } catch [UnauthorizedAccessException] {"""
    probe_start = probe.index('        try {')
    probe = probe[probe_start:]
    if expected not in probe:
        raise ValueError('Unexpected write probe boundary')
    probe = probe.replace(expected, """        try {
            Invoke-EuiWriteProbe $addons
        } catch [UnauthorizedAccessException] {""", 1)
    # Reuse the already downloaded archive after elevation; the child validates it again.
    marker = '            $command = "& \'$quotedPath\' -AddOnsPath'
    if marker not in probe:
        raise ValueError('Unexpected elevation boundary')
    probe = probe.replace(marker, "            $quotedArchive = $ArchivePath.Replace(\"'\", \"''\")\n" + marker, 1)
    probe = probe.replace("-ReportPath '$quotedResult';", "-ReportPath '$quotedResult' -ArchivePath '$quotedArchive';", 1)
    text = text[:start] + text[end:]
    transaction = '        $installResult = Install-Prepared $stage $addons'
    if text.count(transaction) != 1:
        raise ValueError('Unexpected portable transaction boundary')
    text = text.replace(transaction, probe + transaction, 1)
    text = text.replace('    if (-not $PrepareOnly) {\n        $ArchivePath = Join-Path $work',
                        '    if (-not $PrepareOnly -and -not $ArchivePath) {\n        $ArchivePath = Join-Path $work', 1)
    return text


def build(source, output, ptr, refresh=False):
    if output.resolve().is_relative_to(ROOT):
        raise ValueError('Portable ZIPs must be outside the checkout')
    if output.exists():
        raise ValueError('Output already exists')
    script = 'Install-EUI-PTR.ps1' if ptr else 'Install-EUI-Retail.ps1'
    target = '12.1.7-PTR-features' if ptr else 'new-features'
    with zipfile.ZipFile(source) as archive:
        roots = {n.split('/')[0] for n in archive.namelist()}
        if len(roots) != 1:
            raise ValueError('Expected one portable root')
        prefix = roots.pop() + '/'
        entries = {}
        seen = set()
        for info in archive.infolist():
            p = PurePosixPath(info.filename)
            if p.is_absolute() or '..' in p.parts or '\\' in info.filename or ':' in info.filename:
                raise ValueError('Unsafe input ZIP path')
            if info.filename.casefold() in seen or (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Duplicate or link in ZIP')
            seen.add(info.filename.casefold())
            if info.is_dir():
                continue
            # Historical exports are not installer dependencies; keep original archives untouched.
            if info.filename.startswith(prefix + 'Installable ZIP/'):
                continue
            entries[info.filename] = archive.read(info)
        for name in (script, 'Export-InstallableZIP.ps1'):
            key = prefix + name
            text = entries[key].decode('utf-8-sig').replace('\r\n', '\n')
            if refresh:
                if prefix + 'PACKAGING.txt' not in entries:
                    raise ValueError('Refresh requires a previously generated shared-helper bundle')
                if name == script and f"New-EuiPackage -Source $source -Staging $stage -Target '{target}'" not in text:
                    raise ValueError('Refresh bundle has an unexpected target/preparation adapter')
                if name != script and 'Export hash differs: $relative' not in text:
                    raise ValueError('Refresh bundle lacks validated exporter boundaries')
            else:
                text = adapt(text, target) if name == script else exporter(text)
            if name == script:
                text = correct_portable(text, target)
            entries[key] = b'\xef\xbb\xbf' + text.replace('\n', '\r\n').encode('utf-8')
        for helper in ('eui-package.ps1', 'eui-install-safety.ps1'):
            entries[prefix + helper] = (ROOT / '.tools/install' / helper).read_bytes()
        entries[prefix + 'PACKAGING.txt'] = (
            'Packaging uses the downloaded snapshot .pkgmeta and .tools/toc_policy.json.\r\n'
            'Only literal relative paths are supported; unsupported YAML and directives fail closed.\r\n'
            'Libraries are taken from the snapshot, never downloaded from externals.\r\n'
            'Historical Installable ZIP exports are omitted; regenerate with the exporter.\r\n'
            'Portable record locations, formats and transaction routines remain unchanged.\r\n'
            'The repository transaction helper is bundled for path/archive/payload validation only.\r\n'
        ).encode('ascii')
        with zipfile.ZipFile(output, 'x', compression=zipfile.ZIP_DEFLATED) as result:
            for name, data in sorted(entries.items()):
                result.writestr(name, data)
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--ptr', action='store_true')
    parser.add_argument('--refresh', action='store_true', help='Refresh helpers in a previously generated bundle')
    args = parser.parse_args()
    print(build(args.input, args.output, args.ptr, args.refresh))
