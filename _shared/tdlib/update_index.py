"""Regenerate the mod tables in the top-level README.md / README.ru.md from each mod's info.txt.

The table sits between <!-- mods --> and <!-- /mods --> markers.
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def read_info(path):
    kv = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            if "=" in line:
                k, v = line.split("=", 1)
                kv[k.strip()] = v.strip()
    return kv


def main() -> int:
    mods = []
    for name in sorted(os.listdir(ROOT)):
        info = os.path.join(ROOT, name, "mod", "info.txt")
        if os.path.isfile(info):
            kv = read_info(info)
            desc = kv.get("description", "")
            en, _, ru = desc.partition(" / ")
            mods.append((name, kv.get("en_name", kv.get("name", name)), kv.get("ru_name", name), en.strip(), (ru or en).strip()))
    tables = {
        "README.md": ("| Folder | Mod | What it is |\n|---|---|---|\n", lambda m: f"| [{m[0]}]({m[0]}) | {m[1]} | {m[3]} |"),
        "README.ru.md": ("| Папка | Мод | Что это |\n|---|---|---|\n", lambda m: f"| [{m[0]}]({m[0]}) | {m[2]} | {m[4]} |"),
    }
    for fname, (head, row) in tables.items():
        p = os.path.join(ROOT, fname)
        s = open(p, encoding="utf-8").read()
        block = "<!-- mods -->\n" + head + "\n".join(row(m) for m in mods) + "\n<!-- /mods -->"
        if "<!-- mods -->" not in s:
            raise SystemExit(f"{fname}: markers missing")
        s = re.sub(r"<!-- mods -->.*?<!-- /mods -->", lambda _: block, s, flags=re.S)
        open(p, "w", encoding="utf-8").write(s)
    print(f"index: {len(mods)} mods")
    return 0


if __name__ == "__main__":
    sys.exit(main())
