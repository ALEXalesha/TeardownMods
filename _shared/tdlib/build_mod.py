"""Generic build + check runner for a mod repository.

    python build_mod.py <mod_root>

Runs tools/build_vox.py, tools/build_sounds.py, tools/build_images.py (those
that exist), then check_mod.py on mod/ and the harness on every tests/*.lua.
"""
from __future__ import annotations

import glob
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def main(root: str) -> int:
    root = os.path.abspath(root)
    steps = []
    for name in ("build_vox.py", "build_sounds.py", "build_images.py", "build_options.py"):
        p = os.path.join(root, "tools", name)
        if os.path.isfile(p):
            steps.append([sys.executable, p])
    steps.append([sys.executable, os.path.join(HERE, "check_mod.py"), os.path.join(root, "mod")])
    for sc in sorted(glob.glob(os.path.join(root, "tests", "*.lua"))):
        steps.append([sys.executable, os.path.join(HERE, "..", "harness", "run.py"), os.path.join(root, "mod"), sc, "--quiet"])
    for cmd in steps:
        print(">>", os.path.basename(cmd[1]), *(os.path.basename(c) for c in cmd[2:3]))
        r = subprocess.run(cmd, cwd=root)
        if r.returncode != 0:
            print("FAILED:", " ".join(cmd))
            return r.returncode
    print("ALL STEPS OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else os.getcwd()))
