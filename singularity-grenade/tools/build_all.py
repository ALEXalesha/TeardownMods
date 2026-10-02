"""Rebuild every generated asset of the mod and run all offline checks.

    ..\_shared\.venv\Scripts\python tools\build_all.py
"""
from __future__ import annotations

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SHARED = os.path.join(ROOT, "..", "_shared")

STEPS = [
    [sys.executable, os.path.join(HERE, "build_vox.py")],
    [sys.executable, os.path.join(HERE, "build_sounds.py")],
    [sys.executable, os.path.join(HERE, "build_images.py")],
    [sys.executable, os.path.join(SHARED, "tdlib", "check_mod.py"), os.path.join(ROOT, "mod")],
    [sys.executable, os.path.join(SHARED, "harness", "run.py"), os.path.join(ROOT, "mod"),
     os.path.join(ROOT, "tests", "scenarios.lua"), "--quiet"],
]

if __name__ == "__main__":
    for cmd in STEPS:
        print(">>", os.path.basename(cmd[1]))
        r = subprocess.run(cmd, cwd=ROOT)
        if r.returncode != 0:
            print("FAILED:", " ".join(cmd))
            sys.exit(r.returncode)
    print("ALL STEPS OK")
