"""Run the actual Nameplates page builder with a Lua 5.1 widget recorder."""

import argparse
import ctypes
import os
from pathlib import Path
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lua_runtime import LuaDLL, dll_candidates


def run_dll(path, source):
    lua = LuaDLL(str(path))
    if lua.version() != "Lua 5.1":
        raise RuntimeError("Expected a Lua 5.1 DLL")
    lua.lib.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
    lua.lib.lua_pcall.restype = ctypes.c_int
    state = lua.state()
    try:
        lua.lib.luaL_openlibs(state)
        if (lua.lib.luaL_loadbuffer(state, source, len(source), b"=Nameplates Extras")
                or lua.lib.lua_pcall(state, 0, 0, 0)):
            raise RuntimeError(lua.lib.lua_tolstring(state, -1, None).decode("utf-8", "replace"))
    finally:
        lua.lib.lua_close(state)


def run(source):
    dll = os.environ.get("LUA51_DLL")
    executable = os.environ.get("LUA51")
    if not dll and not executable:
        executable = shutil.which("lua5.1") or shutil.which("lua")
        if not executable and sys.platform == "win32":
            dll = next((path for path in dll_candidates(os.environ) if path.is_file()), None)
    if dll:
        run_dll(dll, source)
        return
    if not executable:
        raise RuntimeError("Set LUA51 to a Lua 5.1 interpreter or LUA51_DLL to an existing Windows Lua 5.1 DLL")
    subprocess.run([executable, "-"], input=source, check=True, timeout=30)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[2] /
                        "EllesmereUIOptions/Nameplates_Options/GeneralPage_Options.lua")
    args = parser.parse_args()
    try:
        harness = Path(__file__).with_suffix(".lua").read_bytes()
        run(b'assert(_VERSION == "Lua 5.1", "Expected a Lua 5.1 interpreter")\n' +
            harness + b"\ncheck(function()\n" + args.source.read_bytes() +
            b'\nend)\nprint("Nameplates Extras: all 8 destination CVar combinations passed")\n')
    except (OSError, RuntimeError, AttributeError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Nameplates Extras layout check failed: {error}\n")


if __name__ == "__main__":
    main()
