"""Look up Teardown API documentation blocks in data/script_defs.lua.

Usage: python apidoc.py FuncName [FuncName ...]
       python apidoc.py --names        (print all function names)
"""
from __future__ import annotations

import os
import re
import sys

TEARDOWN = os.environ.get("TEARDOWN_DIR", r"C:\Program Files (x86)\Steam\steamapps\common\Teardown")
DEFS = os.path.join(TEARDOWN, "data", "script_defs.lua")

_FUNC_RE = re.compile(r"^function ([A-Za-z_][A-Za-z0-9_.]*)\s*\(([^)]*)\)")


def parse_defs(path: str = DEFS) -> dict[str, dict]:
    """Return {name: {"params": [...], "doc": str, "returns": int, "optional": [...]}}."""
    out: dict[str, dict] = {}
    doc: list[str] = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("---"):
                doc.append(line[3:])
                continue
            m = _FUNC_RE.match(line)
            if m:
                name = m.group(1)
                params = [p.strip() for p in m.group(2).split(",") if p.strip()]
                optional = []
                required = []
                nret = 0
                for d in doc:
                    pm = re.match(r"@param\s+(\S+?)(\?)?\s", d + " ")
                    if pm:
                        (optional if pm.group(2) else required).append(pm.group(1))
                    if d.startswith("@return"):
                        nret += 1
                out[name] = {
                    "params": params,
                    "doc": "\n".join(doc),
                    "returns": nret,
                    "optional": optional,
                    "required": required,
                    "varargs": "..." in params,
                }
                doc = []
            elif line.strip() == "":
                pass
            else:
                doc = []
    return out


if __name__ == "__main__":
    defs = parse_defs()
    if len(sys.argv) > 1 and sys.argv[1] == "--names":
        print("\n".join(sorted(defs)))
        sys.exit(0)
    for n in sys.argv[1:]:
        d = defs.get(n)
        if not d:
            print(f"### {n}: NOT FOUND")
            continue
        body = "\n".join(l for l in d["doc"].splitlines() if l.strip() and not l.startswith(" ") and "```" not in l)
        lines = [l for l in d["doc"].splitlines()]
        # drop example code blocks
        keep, in_code = [], False
        for l in lines:
            if "```" in l:
                in_code = not in_code
                continue
            if not in_code and l.strip() and l.strip() != "Example:":
                keep.append(l.strip())
        print(f"### {n}({', '.join(d['params'])})")
        print("\n".join(keep))
        print()
