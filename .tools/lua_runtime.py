"""Resolve an existing Lua 5.1 compiler without installing or configuring tools."""
from __future__ import annotations

import argparse
import ctypes
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


PROBES = (
    (b"local x = 1\n", True, "valid Lua"),
    (b"local x = = 1\n", False, "invalid syntax"),
    (("local " + ",".join("v%d" % i for i in range(201)) + "\n").encode(), False, "200-local limit"),
    (("local " + ",".join("v%d" % i for i in range(61)) + "\nlocal function f() return "
      + ",".join("v%d" % i for i in range(61)) + " end\n").encode(), False, "60-upvalue limit"),
)


class LuaDLL:
    """Compile only; never execute the addon sources being checked."""

    def __init__(self, filename):
        self.lib = ctypes.CDLL(filename)
        # These exports distinguish the 5.1 API before using its globals index.
        self.lib.lua_getfenv
        self.lib.lua_setfenv
        self.lib.luaL_newstate.restype = ctypes.c_void_p
        self.lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
        self.lib.lua_getfield.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_char_p]
        self.lib.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
        self.lib.luaL_loadbuffer.restype = ctypes.c_int
        self.lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
        self.lib.lua_tolstring.restype = ctypes.c_char_p
        self.lib.lua_close.argtypes = [ctypes.c_void_p]

    def state(self):
        state = self.lib.luaL_newstate()
        if not state:
            raise RuntimeError("Lua 5.1 could not allocate a compiler state")
        return state

    def version(self):
        state = self.state()
        try:
            self.lib.luaL_openlibs(state)
            self.lib.lua_getfield(state, -10002, b"_VERSION")
            return self.lib.lua_tolstring(state, -1, None).decode("ascii")
        finally:
            self.lib.lua_close(state)

    def compile(self, source):
        state = self.state()
        try:
            code = self.lib.luaL_loadbuffer(state, source, len(source), b"=stdin")
            error = self.lib.lua_tolstring(state, -1, None) if code else None
            return code, error.decode("utf-8", "replace") if error else ""
        finally:
            self.lib.lua_close(state)


def validate_probes(compile_source):
    for source, should_pass, label in PROBES:
        code, _ = compile_source(source)
        if (code == 0) != should_pass:
            raise RuntimeError("Lua compiler failed the %s probe" % label)


def native_compiler(filename, run):
    result = run([filename, "-v"], capture_output=True, stdin=subprocess.DEVNULL, timeout=10)
    version = (result.stdout + result.stderr).decode("utf-8", "replace").strip()
    if result.returncode or not re.search(r"\bLua 5\.1(?:\.|\s|$)", version):
        raise RuntimeError("'%s' is not a Lua 5.1 compiler (%s); set LUAC to a luac 5.1"
                           % (filename, version.splitlines()[0] if version else "no version"))

    def compile_source(source):
        checked = run([filename, "-p", "-"], input=source, capture_output=True, timeout=10)
        return checked.returncode, checked.stderr

    validate_probes(compile_source)
    filename = str(Path(filename).resolve())
    return {"mode": "native", "compiler": filename, "version": version, "command": [filename]}


def dll_compiler(filename):
    filename = str(Path(filename).resolve())
    if not Path(filename).is_file():
        raise RuntimeError("Lua 5.1 DLL does not exist: " + filename)
    compiler = LuaDLL(filename)
    if compiler.version() != "Lua 5.1":
        raise RuntimeError("The configured DLL is not Lua 5.1")
    validate_probes(compiler.compile)
    return {"mode": "dll", "compiler": filename, "version": "Lua 5.1",
            "command": [sys.executable, "-B", str(Path(__file__).resolve()), "--dll", filename]}


def dll_candidates(environment):
    """Known installed application locations, never a repository-wide search."""
    roots = []
    profile = environment.get("USERPROFILE")
    if profile:
        roots.append(Path(profile) / "AppData/Local/Programs")
    for name in ("ProgramFiles", "ProgramFiles(x86)"):
        if environment.get(name):
            roots.append(Path(environment[name]))
    tail = "resources/app.asar.unpacked/node_modules/noobs/dist/bin/lua51.dll"
    return [root / application / tail for root in roots
            for application in ("WarcraftRecorder", "Warcraft Recorder")]


def resolve(environment=None, platform=None, which=None, run=None):
    environment = os.environ if environment is None else environment
    platform = sys.platform if platform is None else platform
    which = which or shutil.which
    run = run or subprocess.run
    configured = environment.get("LUAC")
    if configured:
        executable = which(configured)
        if not executable:
            raise RuntimeError("no Lua 5.1 compiler '%s': install lua5.1 (luac5.1 on PATH) "
                               "or set LUAC=/path/to/luac" % configured)
        return native_compiler(executable, run)
    configured_dll = environment.get("LUA51_DLL")
    if configured_dll:
        if platform != "win32":
            raise RuntimeError("LUA51_DLL requires Windows; configure a native Lua 5.1 compiler")
        return dll_compiler(configured_dll)
    errors = []
    for name in ("luac5.1", "luac"):
        executable = which(name)
        if executable:
            try:
                return native_compiler(executable, run)
            except (OSError, RuntimeError, subprocess.SubprocessError) as error:
                errors.append(str(error))
    if platform == "win32":
        for filename in dll_candidates(environment):
            if filename.is_file():
                try:
                    return dll_compiler(str(filename))
                except (OSError, AttributeError, RuntimeError) as error:
                    errors.append(str(error))
    detail = "; ".join(errors)
    raise RuntimeError("No compatible Lua 5.1 compiler; set LUAC to an existing compiler"
                       + (" or LUA51_DLL to an existing Lua 5.1 DLL" if platform == "win32" else "")
                       + (": " + detail if detail else ""))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resolve", action="store_true", help="Print the validated compiler descriptor")
    parser.add_argument("--dll", help="Use this exact existing Lua 5.1 DLL")
    parser.add_argument("-v", action="store_true", help="Print the DLL's Lua version")
    parser.add_argument("-p", metavar="SOURCE", help="Compile without executing; '-' reads standard input")
    args = parser.parse_args()
    try:
        if args.resolve:
            if args.dll or args.v or args.p:
                parser.error("--resolve cannot be combined with compiler arguments")
            print(json.dumps(resolve()))
            return 0
        if not args.dll or not (args.v or args.p):
            parser.error("Use --resolve, or --dll with -v or -p")
        if sys.platform != "win32":
            raise RuntimeError("The Lua DLL compiler requires Windows")
        compiler = LuaDLL(args.dll)
        if compiler.version() != "Lua 5.1":
            raise RuntimeError("The configured DLL is not Lua 5.1")
        if args.v:
            print("Lua 5.1")
            return 0
        source = sys.stdin.buffer.read() if args.p == "-" else Path(args.p).read_bytes()
        code, error = compiler.compile(source)
        if error:
            print(error, file=sys.stderr)
        return code
    except (OSError, AttributeError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
