#!/usr/bin/env python3
"""Summarize library changes in a local Git range without network access."""

import argparse
import json
import re
import subprocess
import sys


def git(*args):
    try:
        result = subprocess.run(["git", *args], capture_output=True, check=False)
    except OSError as error:
        raise RuntimeError(f"Could not run Git: {error}") from error
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"Git failed ({result.returncode}): {detail}")
    return result.stdout


def tree_at(ref):
    return git("rev-parse", "--verify", f"{ref}^{{tree}}").decode("ascii").strip()


def externals_at(tree):
    entries = git("ls-tree", "-z", tree, "--", ".pkgmeta")
    if not entries:
        return {}
    if len(entries.split(b"\0")) != 2:
        raise RuntimeError("Unexpected .pkgmeta tree entry")
    metadata, separator, path = entries[:-1].partition(b"\t")
    fields = metadata.split()
    if not separator or path != b".pkgmeta" or len(fields) != 3 or fields[1] != b"blob":
        raise RuntimeError(".pkgmeta is not a readable blob")
    content = git("cat-file", "blob", fields[2].decode("ascii")).decode("utf-8")

    paths = {}
    inside = False
    current = None
    for line in content.splitlines():
        value = line.strip()
        if value == "externals:":
            inside = True
            continue
        if not inside or not value:
            continue
        indent = len(line) - len(line.lstrip(" "))
        if indent == 0:
            break
        if indent <= 2 and re.fullmatch(r"[^:]+:", value):
            current = value[:-1]
            paths[current] = {}
        elif current and ":" in value:
            key, entry = value.split(":", 1)
            paths[current][key] = entry.strip()
    return paths


def classify(base, head):
    old_tree = tree_at(base)
    new_tree = tree_at(head)
    old = externals_at(old_tree)
    new = externals_at(new_tree)
    externals = set(old) | set(new)
    fields = git("diff", "--no-renames", "--name-status", "-z", old_tree, new_tree, "--").split(b"\0")
    groups = {}
    metadata_status = None

    for status, raw_path in zip(fields[0::2], fields[1::2]):
        path = raw_path.decode("utf-8", errors="surrogateescape")
        if path == ".pkgmeta":
            continue
        if path == ".pkgmeta-lock.json":
            metadata_status = status.decode("ascii")
            continue
        library = next((item for item in sorted(externals, key=len, reverse=True)
                        if path == item or path.startswith(item + "/")), None)
        if library is None:
            parts = path.split("/")
            if "Libs" in parts:
                index = parts.index("Libs")
                if index + 1 < len(parts):
                    library = "/".join(parts[:index + 2])
        if library is not None:
            group = groups.setdefault(library, {"files": 0, "statuses": set()})
            group["files"] += 1
            group["statuses"].add(status.decode("ascii"))

    for library in externals:
        if old.get(library) != new.get(library):
            groups.setdefault(library, {"files": 0, "statuses": set()})

    changes = []
    for library, group in sorted(groups.items()):
        if library in externals:
            action = "A" if library not in old else "D" if library not in new else "M"
        else:
            action = next(iter(group["statuses"])) if len(group["statuses"]) == 1 else "M"
        changes.append({"library": library, "status": action, "files": group["files"]})
    if metadata_status is not None:
        changes.append({"library": "metadata", "status": metadata_status, "files": 1})
    return {"changes": changes}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base", help="Merge base before the upstream sync")
    parser.add_argument("head", help="Fetched upstream ref")
    args = parser.parse_args()
    try:
        print(json.dumps(classify(args.base, args.head), separators=(",", ":")))
    except (RuntimeError, UnicodeError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
