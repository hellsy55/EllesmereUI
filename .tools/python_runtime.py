#!/usr/bin/env python3
"""Resolve and validate one maintenance runtime; never mutate Git or install tools.

Keep this bootstrap parseable by Python 2 so it can reject that runtime clearly.
"""
from __future__ import print_function

import json
import os
import subprocess
import sys

ERROR = "Maintenance tools require a working Python 3 runtime; stop before modifying branches."
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HELPERS = (".tools/release_target.py", ".tools/classify_library_range.py",
           ".tools/check_lib_updates.py")
PROBE = "import json,sys; print(json.dumps([sys.executable,list(sys.version_info[:3])]))"


def candidates(platform):
    return [("py", "-3"), ("python",), ("python3",)] if platform == "win32" else [("python3",), ("python",)]


def resolve(platform=None, run=None, current=None):
    if sys.version_info[0] != 3:
        raise RuntimeError(ERROR)
    run = run or subprocess.run
    commands = candidates(platform or sys.platform)
    # The bootstrap may have been launched by an absolute interpreter path.
    commands.append((current or sys.executable,))
    for command in commands:
        try:
            result = run(list(command) + ["-c", PROBE], capture_output=True,
                         universal_newlines=True, timeout=10)
            if result.returncode:
                continue
            executable, version = json.loads(result.stdout)
            if (not isinstance(executable, str) or not os.path.isabs(executable)
                    or len(version) != 3 or version[0] != 3):
                continue
            # Validate the exact pinned interpreter and every runtime helper.
            # --help exits before Git, network, or vendoring operations.
            for helper in HELPERS:
                checked = run([executable, "-B", os.path.join(ROOT, helper), "--help"],
                              capture_output=True, universal_newlines=True, timeout=10)
                if checked.returncode:
                    break
            else:
                return {"python": executable, "version": ".".join(str(part) for part in version)}
        except (OSError, subprocess.TimeoutExpired, ValueError, TypeError):
            continue
    raise RuntimeError(ERROR)


def main():
    try:
        print(json.dumps(resolve(), separators=(",", ":")))
        return 0
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
