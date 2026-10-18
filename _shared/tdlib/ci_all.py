"""Every offline check of every mod, without rebuilding assets (CI and local use):
the harness on every tests/*.lua, check_mod.py on every mod folder, the upload check of every
upload folder, the upload check's self-test and the key law of all mods together (keymap.py:
no key does two things when several mods are on). Exit code 1 if anything fails.

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
    import keymap
    kfails = keymap.self_test()
    kprobs = keymap.check(keymap.KEYMAP, keymap.read_sources()) + keymap.stale_readmes()
    print("key law:", "OK" if not (kfails or kprobs) else "FAIL")
    for p in kprobs:
        print("  KEY CLASH:", p)
    if kfails:
        print("  key law self-test missed:", ", ".join(kfails))
    if kfails or kprobs:
        failed.append("key law")
    # options screens: every label narrower than its column in the game's font (review 17.10: the catapult's
    # 471 px label ran into its button in a 330 px column); the self-test plants a label that is too long
    import options_gen
    import tempfile
    oprobs = []
    for f in sorted(glob.glob(os.path.join(ROOT, "*", "mod", "options.lua"))):
        oprobs += options_gen.check_options(f)
    with tempfile.TemporaryDirectory() as d:
        bad = os.path.join(d, "probe", "mod", "options.lua")
        os.makedirs(os.path.dirname(bad))
        with open(bad, "w", encoding="utf-8") as fh:
            fh.write('local LABEL_W = 330\n\t{ kind = "choice", key = "x", label = { "Fall damage for a launched player", '
                     '"Урон от падения для запущенного игрока" } },\n')
        missed = not options_gen.check_options(bad)
    print("options labels:", "OK" if not (oprobs or missed) else "FAIL")
    for p in oprobs:
        print("  LABEL:", p)
    if missed:
        print("  options label law self-test missed a 471 px label in a 330 px column")
    if oprobs or missed:
        failed.append("options labels")
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
