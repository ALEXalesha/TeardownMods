"""Teardown material palette ranges.

Source: the annotated palette shipped with the game, data/built-in/palette.vox
(and mods/editorshowcase/main/teardown_palette.vox): its MagicaVoxel NOTE chunk
names each palette row of 8 entries. Rows listed bottom-up give these ranges.
The material is decided by the index; colour and MATL (metal/glass/emit look)
are free.
"""
from __future__ import annotations

RANGES = [
    ("glass", 1, 8), ("grass", 9, 24), ("dirt", 25, 40), ("rock", 41, 56), ("wood", 57, 72),
    ("concrete", 73, 88), ("brick", 89, 104), ("plaster", 105, 120), ("weak metal", 121, 136),
    ("heavy metal", 137, 152), ("plastic", 153, 168), ("hard metal", 169, 176), ("hard masonry", 177, 184),
    ("reserved", 185, 224), ("unphysical", 225, 240), ("reserved", 241, 255),
]


def material_of(index: int) -> str:
    for name, a, b in RANGES:
        if a <= index <= b:
            return name
    return "none"


def read_palette_notes(path: str) -> list[str]:
    """Row names from a .vox NOTE chunk (32 rows, top row first)."""
    import struct
    with open(path, "rb") as f:
        b = f.read()
    o = 20
    while o < len(b):
        cid = b[o:o + 4]
        cl, chl = struct.unpack_from("<ii", b, o + 4)
        c = b[o + 12:o + 12 + cl]
        if cid == b"NOTE":
            n, = struct.unpack_from("<i", c, 0)
            p = 4
            names = []
            for _ in range(n):
                ln, = struct.unpack_from("<i", c, p)
                p += 4
                names.append(c[p:p + ln].decode("utf-8", "replace"))
                p += ln
            return names
        o += 12 + cl + chl
    return []


def verify_against_game(teardown_dir: str) -> list[str]:
    """Compare RANGES with the game's annotated palette; returns mismatches."""
    import os
    names = read_palette_notes(os.path.join(teardown_dir, "data", "built-in", "palette.vox"))
    rows = list(reversed(names))  # row 0 = indices 1..8
    problems = []
    for row, name in enumerate(rows):
        for idx in range(row * 8 + 1, row * 8 + 9):
            if idx > 255:
                continue
            ours = material_of(idx)
            if ours != name:
                problems.append(f"index {idx}: game says {name}, palette.py says {ours}")
    return problems


if __name__ == "__main__":
    import sys
    from apidoc import TEARDOWN
    probs = verify_against_game(TEARDOWN)
    print("palette ranges match the game's annotated palette" if not probs else "\n".join(probs[:20]))
    sys.exit(1 if probs else 0)
