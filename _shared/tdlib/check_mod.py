"""Static checks for a Teardown mod folder.

    python check_mod.py <mod_dir> [--list-api]

* every .lua file compiles under Lua 5.1 after resolving #include/#version
* every Capitalised call in the sources is either in script_defs.lua or
  defined by the mod itself (or by an included game script)
* every "MOD/..." path referenced from .lua / .xml exists
* info.txt has the required keys and the preview exists and is < 1 MB
"""
from __future__ import annotations

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "harness"))
from apidoc import parse_defs  # noqa: E402
from run import preprocess  # noqa: E402

import lupa.lua51 as lua51  # noqa: E402

LUA_KEYWORDS = {"Vec", "Quat", "Transform"}


def strip_comments_and_strings(src: str) -> str:
    src = re.sub(r"--\[(=*)\[.*?\]\1\]", " ", src, flags=re.S)
    src = re.sub(r"--[^\n]*", " ", src)
    src = re.sub(r"\[(=*)\[.*?\]\1\]", '""', src, flags=re.S)
    src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)
    src = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", src)
    return src


def main() -> int:
    mod = os.path.abspath(sys.argv[1])
    list_api = "--list-api" in sys.argv
    defs = parse_defs()
    lua = lua51.LuaRuntime()
    problems: list[str] = []
    api_used: set[str] = set()
    lua_files = []
    for root, _, files in os.walk(mod):
        for f in files:
            if f.endswith(".lua"):
                lua_files.append(os.path.join(root, f))
    for path in sorted(lua_files):
        rel = os.path.relpath(path, mod)
        try:
            src, version = preprocess(path, mod)
        except SystemExit as e:
            problems.append(f"{rel}: {e}")
            continue
        # compile only (the include calls are just function calls here)
        ok = lua.eval("function(s, n) local f, e = loadstring(s, n) if f then return true end return e end")(src, "@" + rel)
        if ok is not True:
            problems.append(f"{rel}: Lua 5.1 compile error: {ok}")
        with open(path, encoding="utf-8") as f:
            raw = f.read()
        clean = strip_comments_and_strings(raw)
        # names defined by the mod itself (global or local functions, tables)
        defined = set(re.findall(r"function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", clean))
        defined |= set(re.findall(r"local\s+function\s+([A-Za-z_][A-Za-z0-9_]*)", clean))
        defined |= set(re.findall(r"(?:^|\n)\s*(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=", clean))
        # names defined by included game scripts
        for inc in re.findall(r'#include\s+"([^"]+)"', raw):
            for cand in (os.path.join(mod, inc), os.path.join(os.path.dirname(path), inc),
                         os.path.join(os.environ.get("TEARDOWN_DIR", r"C:\Program Files (x86)\Steam\steamapps\common\Teardown"), "data", inc)):
                if os.path.isfile(cand):
                    with open(cand, encoding="utf-8", errors="replace") as f:
                        isrc = strip_comments_and_strings(f.read())
                    defined |= set(re.findall(r"function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", isrc))
                    break
        for name in re.findall(r"(?<![.:\w])([A-Z][A-Za-z0-9_]*)\s*\(", clean):
            if name in defs:
                api_used.add(name)
            elif name not in defined:
                problems.append(f"{rel}: call to unknown function {name}()")
        for p in re.findall(r"MOD/[A-Za-z0-9_./-]+", raw):
            if p.endswith("/") or p.endswith("."):
                # built by concatenation ("MOD/snd/" .. name .. ".ogg"): the folder must exist
                if not os.path.isdir(os.path.join(mod, p[4:].rstrip("./"))):
                    problems.append(f"{rel}: missing folder {p}")
                continue
            if not os.path.isfile(os.path.join(mod, p[4:])):
                problems.append(f"{rel}: missing file {p}")
    for root, _, files in os.walk(mod):
        for f in files:
            if f.endswith(".xml"):
                path = os.path.join(root, f)
                with open(path, encoding="utf-8") as fh:
                    raw = fh.read()
                for p in re.findall(r"MOD/[A-Za-z0-9_./-]+\.(?:vox|xml|ogg|png|jpg|lua)", raw):
                    if not os.path.isfile(os.path.join(mod, p[4:])):
                        problems.append(f"{os.path.relpath(path, mod)}: missing file {p}")
    # world-spawned vox files must use real material ranges (not reserved/unphysical)
    from palette import material_of
    from voxio import read_vox
    spawned = set()
    for path in lua_files:
        with open(path, encoding="utf-8") as f:
            raw = f.read()
        for xml in re.findall(r"<body.*?</body>", raw):
            for v in re.findall(r"vox file=['\"](MOD/[^'\"]+)['\"]", xml):
                spawned.add(v)
    for v in sorted(spawned):
        full = os.path.join(mod, v[4:])
        if not os.path.isfile(full):
            continue
        vf = read_vox(full)
        mats = {}
        for m in vf.models:
            for idx in m.voxels.values():
                mats.setdefault(material_of(idx), set()).add(idx)
        bad = {k: sorted(x) for k, x in mats.items() if k in ("reserved", "unphysical", "none")}
        print(f"  spawned {v}: " + ", ".join(f"{k} {min(x)}-{max(x)}" for k, x in sorted(mats.items())))
        if bad:
            problems.append(f"{v}: world-spawned vox uses non-material palette indices {bad}")
    info = os.path.join(mod, "info.txt")
    if not os.path.isfile(info):
        problems.append("info.txt missing")
    else:
        kv = {}
        with open(info, encoding="utf-8") as f:
            for line in f:
                if "=" in line:
                    k, v = line.split("=", 1)
                    kv[k.strip()] = v.strip()
        for k in ("name", "author", "description"):
            if not kv.get(k):
                problems.append(f"info.txt: missing '{k}'")
        prev = kv.get("preview", "preview.jpg")
        pp = os.path.join(mod, prev)
        if not os.path.isfile(pp):
            problems.append(f"info.txt: preview {prev} not found")
        elif os.path.getsize(pp) > 1_000_000:
            problems.append(f"preview {prev} is larger than 1 MB")
    print(f"{os.path.basename(mod)}: {len(lua_files)} lua file(s), {len(api_used)} API functions used")
    if list_api:
        print("API:", ", ".join(sorted(api_used)))
    for p in problems:
        print("  PROBLEM:", p)
    print("STATIC CHECK:", "OK" if not problems else f"{len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
