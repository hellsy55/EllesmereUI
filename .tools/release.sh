#!/usr/bin/env bash
# Build a local release zip in .release/ using BigWigsMods/packager (no upload).
# Requires: Python 3, bash, curl, git, svn, zip. EUI_PYTHON can pin Python.
# --publish --tag NAME is reserved for an explicitly authorized release.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap="${EUI_PYTHON:-python3}"
runtime_json="$("$bootstrap" -B "$root/.tools/python_runtime.py")"
export EUI_PYTHON
EUI_PYTHON="$("$bootstrap" -c 'import json,sys; print(json.load(sys.stdin)["python"])' <<< "$runtime_json")"
export EUI_ROOT="$root"
export EUI_RELEASE_TAG=""
selection=()
publish=false
tag_selected=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --target|--tag)
            [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 1; }
            if [ "$1" = --tag ]; then tag_selected=true; EUI_RELEASE_TAG="$2"; fi
            selection+=("$1" "$2"); shift 2 ;;
        --publish) publish=true; shift ;;
        *) echo "Unsupported argument: $1. Use --target BRANCH or --tag NAME." >&2; exit 1 ;;
    esac
done
packager_args=(-d)
if "$publish"; then
    "$tag_selected" || { echo "Publication requires --tag NAME" >&2; exit 1; }
    selection+=(--remote)
    packager_args=()
fi
export EUI_TARGET
EUI_TARGET="$("$EUI_PYTHON" -B "$root/.tools/release_manifest.py" preflight --root "$root" "${selection[@]}")"

# The packager needs these on PATH: svn fetches the WowAce externals in
# .pkgmeta, zip builds the archive. Git for Windows ships neither.
missing=""
for tool in curl git svn zip; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
    echo "Missing on PATH:$missing. Install them first, then run this again." >&2
    exit 1
fi

# One pin shared with the checksum and publication boundary adapter.
PACKAGER_REF="$("$EUI_PYTHON" -c 'import sys; sys.path.insert(0, sys.argv[1]); from release_manifest import PACKAGER_REF; print(PACKAGER_REF)' "$root/.tools")"

script="$(mktemp)"
protected="$(mktemp)"
trap 'rm -f "$script" "$protected"' EXIT

curl -fsSL "https://raw.githubusercontent.com/BigWigsMods/packager/$PACKAGER_REF/release.sh" -o "$script"
"$EUI_PYTHON" -B "$root/.tools/release_manifest.py" protect --output "$protected" "$script"
bash "$protected" "${packager_args[@]}" -t "$root"
