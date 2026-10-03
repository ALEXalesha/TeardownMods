"""Offline harness for Teardown mods.

Runs a mod script (and options.lua) in Lua 5.1 (lupa) against a fake engine
(engine.lua) whose API surface is generated from the game's script_defs.lua.

    python run.py <mod_dir> <scenario.lua> [--split] [--report out.json]

The scenario file is Lua and runs in the harness global environment with the
helper table `T` (see SCENARIO_API below) and the engine table `H`.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tdlib"))
from apidoc import parse_defs, TEARDOWN  # noqa: E402

import lupa.lua51 as lua51  # noqa: E402

DATA = os.path.join(TEARDOWN, "data")

# Functions considered heavy: per-frame budgets are checked against these.
HEAVY = [
    "QueryAabbBodies", "QueryAabbShapes", "QueryRaycast", "QueryClosestPoint", "QueryShot",
    "MakeHole", "Spawn", "SpawnParticle", "ApplyBodyImpulse", "PointLight", "GetShapeMaterialAtPosition",
    "Explosion", "SpawnFire", "Paint", "SetBodyVelocity", "GetBodyClosestPoint", "GetShapeClosestPoint",
    "DrawBodyOutline", "PlaySound", "QueryRaycastWater", "DetachJointFromShape", "Delete",
]


def preprocess(path: str, mod_dir: str, seen: set[str] | None = None, depth: int = 0) -> tuple[str, int]:
    """Resolve Teardown's #include / #version directives. Returns (source, version)."""
    if seen is None:
        seen = set()
    version = 1
    out = []
    with open(path, encoding="utf-8") as f:
        src = f.read()
    if src.startswith("﻿"):
        raise SystemExit(f"{path}: UTF-8 BOM found, Teardown may not like it")
    for line in src.splitlines():
        s = line.strip()
        m = re.match(r'#version\s+(\d+)', s)
        if m:
            version = int(m.group(1))
            out.append("-- " + s)
            continue
        m = re.match(r'#include\s+"([^"]+)"', s)
        if m:
            inc = m.group(1)
            cands = []
            if inc.startswith("MOD/"):
                cands.append(os.path.join(mod_dir, inc[4:]))
            cands.append(os.path.join(os.path.dirname(path), inc))
            cands.append(os.path.join(mod_dir, inc))
            cands.append(os.path.join(DATA, inc))
            found = next((c for c in cands if os.path.isfile(c)), None)
            if not found:
                raise SystemExit(f"{path}: #include not found: {inc}")
            key = os.path.normcase(os.path.abspath(found))
            if key in seen:
                out.append(f"-- #include {inc} (already included)")
                continue
            seen.add(key)
            sub, _ = preprocess(found, mod_dir, seen, depth + 1)
            out.append(f"__H_INCLUDE({lua_quote(sub)}, {lua_quote(inc)})")
            continue
        out.append(line)
    return "\n".join(out), version


def lua_quote(text: str) -> str:
    """Single-line Lua string literal (keeps the parent file's line numbers intact)."""
    bs = chr(92)
    t = text.replace(bs, bs + bs).replace('"', bs + '"').replace(chr(13), "").replace(chr(10), bs + "n")
    return '"' + t + '"'


def build_spec(defs: dict) -> dict:
    spec = {}
    for name, d in defs.items():
        if "." in name:
            continue
        params = []
        doc_params = []
        for l in d["doc"].splitlines():
            m = re.match(r"@param\s+(\S+?)(\?)?\s+(\S+)(.*)", l.strip())
            if m:
                optional = bool(m.group(2)) or "or nil" in m.group(4).lower()
                doc_params.append((m.group(1), m.group(3), optional))
        # map by declared parameter order
        for i, pname in enumerate(d["params"]):
            match = next((p for p in doc_params if p[0] == pname or p[0].lstrip("_") == pname.lstrip("_")), None)
            if match:
                params.append({"n": pname, "t": match[1], "opt": match[2]})
            else:
                params.append({"n": pname, "t": "any", "opt": True})
        rets = []
        for l in d["doc"].splitlines():
            m = re.match(r"@return\s+(\S+)", l.strip())
            if m:
                rets.append(m.group(1))
        varargs = d["varargs"] or any(pn.startswith("_param") for pn in d["params"])
        if varargs:
            params = [p for p in params if not p["n"].startswith("_param")]
        spec[name] = {"params": params, "returns": rets, "varargs": varargs}
    return spec


class Harness:
    def __init__(self, mod_dir: str, split: bool = False):
        self.mod_dir = os.path.abspath(mod_dir)
        self.split = split
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.defs = parse_defs()
        spec = build_spec(self.defs)
        g = self.lua.globals()
        with open(os.path.join(HERE, "engine.lua"), encoding="utf-8") as f:
            self.lua.execute(f.read())
        H = g.H
        self.H = H
        # spec -> lua table
        H.SPEC = self._to_lua(spec)
        H.modDir = self.mod_dir.replace("\\", "/")
        H.dataDir = DATA.replace("\\", "/")
        H.fileExists = lambda p: os.path.isfile(p)
        H.readFile = lambda p: open(p, encoding="utf-8", errors="replace").read()
        H.split = split
        H.preprocess = lambda rel: preprocess(os.path.join(self.mod_dir, rel), self.mod_dir)
        H.voxSizes = lambda path, *_: self._vox_sizes(path)
        H.voxContent = lambda path, *_: self._vox_content(path)
        self.lua.execute("H.wrapAll()")
        with open(os.path.join(HERE, "driver.lua"), encoding="utf-8") as f:
            self.lua.execute(f.read())

    def _vox_content(self, full_path):
        """Per model: min and max index of the filled voxels, Teardown axis order (x, z, y)."""
        try:
            from voxio import read_vox
            vf = read_vox(full_path)
        except Exception:
            return None
        out = []
        for m in vf.models:
            if not m.voxels:
                out.append([0, 0, 0, 0, 0, 0])
                continue
            xs = [k[0] for k in m.voxels]
            ys = [k[1] for k in m.voxels]
            zs = [k[2] for k in m.voxels]
            out.append([min(xs), min(zs), min(ys), max(xs), max(zs), max(ys)])
        return self._to_lua(out)

    def _vox_sizes(self, full_path):
        """Shape sizes of a .vox in Teardown axis order (MagicaVoxel x, z, y)."""
        try:
            from voxio import read_vox
            vf = read_vox(full_path)
        except Exception:
            return None
        return self._to_lua([[m.size[0], m.size[2], m.size[1]] for m in vf.models])

    def _to_lua(self, obj):
        if isinstance(obj, dict):
            t = self.lua.table()
            for k, v in obj.items():
                t[k] = self._to_lua(v)
            return t
        if isinstance(obj, list):
            t = self.lua.table()
            for i, v in enumerate(obj, 1):
                t[i] = self._to_lua(v)
            return t
        return obj

    def load_script(self, rel: str, name: str = "main"):
        path = os.path.join(self.mod_dir, rel)
        src, version = preprocess(path, self.mod_dir)
        self.lua.globals().T.loadScript(name, src, version, rel)
        return version

    def run_scenario(self, scenario_path: str):
        with open(scenario_path, encoding="utf-8") as f:
            code = f.read()
        self.lua.globals().T.runScenario(code, os.path.basename(scenario_path))

    def report(self) -> dict:
        H = self.H
        def lst(t):
            return [t[i] for i in range(1, len(t) + 1)] if t else []
        def dct(t):
            return {k: v for k, v in t.items()} if t else {}
        rep = {
            "errors": lst(H.errors),
            "warnings": lst(H.warnings),
            "unknown": dct(H.unknown),
            "calls": dct(H.calls),
            "maxFrameCalls": dct(H.maxFrameCalls),
            "maxFrameParticles": H.maxFrameParticles,
            "frames": H.frame,
            "checks": lst(self.lua.globals().T.results),
            "log": lst(H.log),
            "server": dct(H.sideCalls.server),
            "client": dct(H.sideCalls.client),
            "legacy": dct(H.sideCalls.legacy),
        }
        return rep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mod_dir")
    ap.add_argument("scenario")
    ap.add_argument("--report")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()
    ok = True
    for split in (False, True):
        h = Harness(args.mod_dir, split=split)
        h.run_scenario(args.scenario)
        rep = h.report()
        generic = set(h.H.genericStubs.keys()) if h.H.genericStubs else set()
        mode = "split server/client VMs" if split else "host (single VM)"
        print(f"=== {os.path.basename(args.scenario)} [{mode}] frames={rep['frames']}")
        passed = sum(1 for c in rep["checks"] if c.startswith("PASS"))
        failed = [c for c in rep["checks"] if not c.startswith("PASS")]
        print(f"checks: {passed} passed, {len(failed)} failed")
        for c in failed:
            print("  " + c)
        if not args.quiet:
            for c in rep["checks"]:
                if c.startswith("PASS"):
                    print("  " + c)
        if rep["errors"]:
            groups = {}
            for e in rep["errors"]:
                first = e.split(chr(10), 1)[0]
                key = first.split("] ", 1)[-1]
                if key not in groups:
                    groups[key] = [0, e]
                groups[key][0] += 1
            print(f"ERRORS ({len(rep['errors'])}, unique {len(groups)}):")
            for key, (cnt, e) in list(groups.items())[:12]:
                lines = e.split(chr(10))
                print(f"  x{cnt} " + lines[0])
                for l in lines[1:6]:
                    if l.strip() and "xpcall" not in l and "<python>" not in l:
                        print("      " + l.strip())
        if rep["unknown"]:
            print("UNKNOWN GLOBALS:", rep["unknown"])
        if rep["warnings"]:
            uniq = sorted(set(w.split("] ", 1)[-1] for w in rep["warnings"]))
            print(f"warnings ({len(rep['warnings'])}, unique {len(uniq)}):")
            for w in uniq[:15]:
                print("  " + w)
        heavy = {k: rep["maxFrameCalls"].get(k) for k in HEAVY if k in rep["maxFrameCalls"]}
        print("max calls per frame (heavy):", heavy, "max particles/frame:", rep["maxFrameParticles"])
        stubs = sorted(k for k in rep["calls"] if k in generic)
        print("API functions called:", len(rep["calls"]), "| answered by generic stubs:", ", ".join(stubs) if stubs else "none")
        ok = ok and not failed and not rep["errors"] and not rep["unknown"]
        if args.report:
            base, ext = os.path.splitext(args.report)
            with open(f"{base}{'_split' if split else '_host'}{ext}", "w", encoding="utf-8") as f:
                json.dump(rep, f, indent=1, ensure_ascii=False)
    print("RESULT:", "OK" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
