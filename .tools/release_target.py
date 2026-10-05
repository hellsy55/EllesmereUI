#!/usr/bin/env python3
"""Resolve the latest release in fetched upstream history without mutating Git."""

import argparse
import json
import re
import subprocess
import sys


def git(*args):
    result = subprocess.run(["git", *args], capture_output=True, check=False)
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"Git failed ({result.returncode}): {detail}")
    return result.stdout.decode("utf-8", errors="replace").strip()


def resolve_release(upstream_ref="upstream/main"):
    # Freeze the fetched head so all returned values describe the same history.
    head = git("rev-parse", "--verify", f"{upstream_ref}^{{commit}}")
    history = git("log", "--topo-order", "--format=%H%x09%s", head)
    for entry in history.splitlines():
        sha, _, subject = entry.partition("\t")
        if re.match(r"^release(?:\s|$)", subject, re.IGNORECASE):
            git("merge-base", "--is-ancestor", sha, head)
            return {
                "upstream_head": head,
                "release_target": sha,
                "release_subject": subject,
                "post_release_commits": int(git("rev-list", "--count", f"{sha}..{head}")),
            }
    raise RuntimeError(
        f"No release commit could be identified in {upstream_ref}. "
        "Stop before modifying any branch; do not fall back to HEAD or a tag. "
        "If history is shallow, fetch complete history and retry."
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream-ref", default="upstream/main", help="Fetched upstream history to inspect")
    args = parser.parse_args()
    try:
        print(json.dumps(resolve_release(args.upstream_ref), separators=(",", ":")))
    except (OSError, RuntimeError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
