"""Every offline check of every mod, without rebuilding assets (CI and local use):
the harness on every tests/*.lua, check_mod.py on every mod folder, the upload check of every
upload folder and the upload check's self-test. Exit code 1 if anything fails.

    python _shared/tdlib/ci_all.py
"""
from __future__ import annotations

import glob
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)


def run(cmd) -> tuple[int, str]:
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def main() -> int:
    import workshop
    failed = []
    fails = workshop.self_test()
    print("upload check self-test:", "OK" if not fails else "FAIL " + "; ".join(fails))
    if fails:
        failed.append("self-test")
    mods = sorted(n for n in os.listdir(ROOT) if os.path.isfile(os.path.join(ROOT, n, "mod", "info.txt")))
    for m in mods:
        mod_dir = os.path.join(ROOT, m, "mod")
        code, out = run([sys.executable, os.path.join(HERE, "check_mod.py"), mod_dir])
        print(f"{m}: check_mod {'OK' if code == 0 else 'FAIL'}")
        if code:
            print(out[-2000:])
            failed.append(m + " check_mod")
        probs = workshop.check_files(workshop.read_folder(mod_dir), tokens=None)
        print(f"{m}: upload check {'OK' if not probs else 'FAIL ' + '; '.join(probs)}")
        if probs:
            failed.append(m + " upload")
        for t in sorted(glob.glob(os.path.join(ROOT, m, "tests", "*.lua"))):
            code, out = run([sys.executable, os.path.join(HERE, "..", "harness", "run.py"), mod_dir, t, "--quiet"])
            ok = code == 0
            print(f"{m}: {os.path.basename(t)} {'OK' if ok else 'FAIL'}")
            if not ok:
                print("\n".join(line for line in out.splitlines() if "FAIL" in line or "rror" in line)[-3000:])
                failed.append(f"{m}/{os.path.basename(t)}")
    print("ALL CHECKS:", "OK" if not failed else f"{len(failed)} failed: " + ", ".join(failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
