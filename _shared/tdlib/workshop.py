"""Steam Workshop preparation and upload check.

    python workshop.py <mod_root>      build Workshop texts + square preview for one mod, then check it
    python workshop.py --all           the same for every mod in the repository (after the self-test)
    python workshop.py --check <dir>   only check a folder as it would be uploaded

What the game needs (read from the game itself, data/ui/components/mod_manager.lua, and from
teardowngame.com/modding):
* the Mod Manager uploads the whole local mod folder (Documents/Teardown/mods/<name>); here that
  folder is a junction to <mod_root>/mod, so tools/ tests/ workshop/ never leave the PC;
* the Steam preview is always <mod folder>/preview.jpg (max 1 MB). The publish window shows it in
  a square frame and refuses to publish without it, so preview.jpg is made square;
* the in-game preview comes from info.txt "preview" and is shown 16:9: thumb.jpg;
* title, description and tags come from info.txt (name, description, tags); valid tags are
  Map, Gameplay, Asset, Vehicle, Tool (Spawn also appears in the game's own mods);
* the first publish writes id.txt (the Steam item id) into the mod folder; later uploads with
  that file become "Publish update". It must be kept (it is committed with the mod).
"""
from __future__ import annotations

import io
import os
import re
import sys
import textwrap

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import art  # noqa: E402
from workshop_data import MODS  # noqa: E402

VALID_TAGS = {"Map", "Gameplay", "Asset", "Vehicle", "Tool", "Spawn"}
ALLOWED_EXT = {".lua", ".txt", ".xml", ".vox", ".ogg", ".png", ".jpg"}
FORBIDDEN_DIRS = {"tests", "tools", "workshop", ".git", "venv", ".venv", "__pycache__", "reports"}
MAX_PREVIEW = 1_000_000
MAX_TOTAL = 50_000_000

# generic personal-data patterns (bytes, lower case). Specific names, addresses and the like
# are read from personal_tokens.txt next to this file, which is git-ignored on purpose.
GENERIC = [b"c:\\drive", b"c:/drive", b"\\users\\user", b"/users/user", b"gmail", b"appdata"]
EMAIL = re.compile(rb"[a-z0-9._%+-]+@[a-z0-9-]+\.[a-z0-9.-]+")
IPV4 = re.compile(rb"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])")
TEXT_EXT = {".lua", ".txt", ".xml"}


def personal_tokens() -> list[bytes]:
    p = os.path.join(HERE, "personal_tokens.txt")
    if not os.path.isfile(p):
        return []
    out = []
    for line in open(p, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            out.append(line.lower().encode("utf-8"))
    return out


# --------------------------------------------------------------------------- texts

def bbcode(d: dict, lang: str) -> str:
    ru = lang == "ru"
    t = d["title_ru"] if ru else d["title"]
    h = (lambda s: f"[h2]{s}[/h2]")
    lines = [f"[h1]{t}[/h1]", d["intro_ru"] if ru else d["intro"], ""]
    lines.append(h("Возможности" if ru else "Features"))
    lines.append("[list]")
    lines += [f"[*]{f}" for f in (d["features_ru"] if ru else d["features"])]
    lines.append("[/list]")
    lines.append(h("Управление" if ru else "Controls"))
    lines.append("[list]")
    for k, a, kr, ar in d["controls"]:
        lines.append(f"[*][b]{kr if ru else k}[/b] - {ar if ru else a}")
    lines.append("[/list]")
    lines.append(h("Настройки (Mod Manager - мод - Options)" if ru else "Settings (Mod Manager - the mod - Options)"))
    lines.append("[list]")
    for n, dv, nr, dr in d["settings"]:
        lines.append(f"[*]{nr if ru else n}: [i]{dr if ru else dv}[/i]")
    lines.append("[/list]")
    lines.append(h("Ограничения" if ru else "Known limits"))
    lines.append("[list]")
    lines += [f"[*]{x}" for x in (d["limits_ru"] if ru else d["limits"])]
    lines.append("[/list]")
    lines.append("")
    lines.append("Свои воксельные модели и синтезированные звуки. Для Teardown 2.x (скрипты #version 2)." if ru else
                 "Own voxel models and synthesized sounds. For Teardown 2.x (#version 2 scripts).")
    return "\n".join(lines) + "\n"


def info_description(d: dict) -> str:
    controls = "; ".join(f"{k} - {a}" for k, a, _, _ in d["controls"])
    return f"{d['intro']} Controls: {controls}. Settings in the Mod Manager (Options)."


def update_info(mod_dir: str, d: dict) -> None:
    p = os.path.join(mod_dir, "info.txt")
    lines = open(p, encoding="utf-8").read().splitlines()
    want = {"name": d["title"], "description": info_description(d), "tags": d["tags"], "preview": "thumb.jpg", "version": "2"}
    seen = set()
    out = []
    for line in lines:
        k = line.split("=", 1)[0].strip() if "=" in line else None
        if k in want:
            out.append(f"{k} = {want[k]}")
            seen.add(k)
        else:
            out.append(line)
    for k, v in want.items():
        if k not in seen:
            out.append(f"{k} = {v}")
    open(p, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")


# --------------------------------------------------------------------------- square preview

def square_preview(mod_dir: str, tagline: str) -> int:
    """preview.jpg for Steam: 1024 x 1024; the 16:9 art in the middle over a blurred, darkened
    copy of itself, a small label on top and the tagline below."""
    thumb = Image.open(os.path.join(mod_dir, "thumb.jpg")).convert("RGBA")
    S = 1024
    bg = thumb.resize((int(thumb.width * S / thumb.height), S), Image.LANCZOS)
    x0 = (bg.width - S) // 2
    bg = bg.crop((x0, 0, x0 + S, S)).filter(ImageFilter.GaussianBlur(28))
    bg = Image.blend(bg, Image.new("RGBA", (S, S), (8, 8, 12, 255)), 0.55)
    wide = thumb.resize((S, int(thumb.height * S / thumb.width)), Image.LANCZOS)
    y = 170
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rectangle((0, y - 6, S, y + wide.height + 6), fill=(0, 0, 0, 160))
    bg.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(10)))
    bg.alpha_composite(wide, (0, y))
    bg = art.text_with_glow(bg, (S // 2, 96), "TEARDOWN MOD", art.font(40), fill=(235, 235, 235), glow=(60, 60, 80), glow_r=6)
    lines = textwrap.wrap(tagline, 30)[:2]
    for i, ln in enumerate(lines):
        bg = art.text_with_glow(bg, (S // 2, y + wide.height + 95 + i * 70), ln, art.font(56), glow=(40, 40, 60), glow_r=8)
    return art.save_jpg(bg, os.path.join(mod_dir, "preview.jpg"))


# --------------------------------------------------------------------------- check

def read_folder(mod_dir: str) -> dict[str, bytes]:
    files = {}
    for dirpath, dirnames, filenames in os.walk(mod_dir):
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, mod_dir).replace("\\", "/")
            with open(full, "rb") as f:
                files[rel] = f.read()
        for dn in list(dirnames):
            rel = os.path.relpath(os.path.join(dirpath, dn), mod_dir).replace("\\", "/")
            files.setdefault(rel + "/", b"")
    return files


def parse_info(data: bytes) -> dict:
    kv = {}
    for line in data.decode("utf-8", "replace").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            kv[k.strip()] = v.strip()
    return kv


def check_files(files: dict[str, bytes], tokens: list[bytes] | None = None) -> list[str]:
    """Problems with a folder as the Mod Manager would upload it (files: relative path -> bytes)."""
    tokens = personal_tokens() if tokens is None else tokens
    problems = []
    total = 0
    for rel, data in sorted(files.items()):
        parts = rel.rstrip("/").split("/")
        if any(p in FORBIDDEN_DIRS for p in parts):
            problems.append(f"{rel}: development folder must not be uploaded")
            continue
        if rel.endswith("/"):
            continue
        total += len(data)
        ext = os.path.splitext(rel)[1].lower()
        if ext not in ALLOWED_EXT:
            problems.append(f"{rel}: file type {ext or '(none)'} must not be uploaded")
        low = data.lower()
        for pat in GENERIC + tokens:
            if pat in low:
                problems.append(f"{rel}: contains personal data ({pat.decode('utf-8', 'replace')[:3]}...)")
        if ext in TEXT_EXT:
            for m in EMAIL.finditer(low):
                problems.append(f"{rel}: contains an e-mail address")
                break
            for m in IPV4.finditer(low):
                problems.append(f"{rel}: contains an IP address")
                break
    if total > MAX_TOTAL:
        problems.append(f"folder is {total // 1_000_000} MB (max {MAX_TOTAL // 1_000_000})")
    info = files.get("info.txt")
    if info is None:
        problems.append("info.txt missing")
        return problems
    kv = parse_info(info)
    for k in ("name", "author", "description", "tags", "preview", "version"):
        if not kv.get(k):
            problems.append(f"info.txt: {k} missing")
    tags = [t.strip() for t in kv.get("tags", "").split(",") if t.strip()]
    for t in tags:
        if t not in VALID_TAGS:
            problems.append(f"info.txt: unknown Workshop tag {t!r}")
    if kv.get("version") and kv["version"] != "2":
        problems.append("info.txt: version must be 2")
    prev = files.get("preview.jpg")
    if prev is None:
        problems.append("preview.jpg missing: the Steam Workshop preview (the publish button stays disabled without it)")
    else:
        if len(prev) > MAX_PREVIEW:
            problems.append(f"preview.jpg is {len(prev) // 1024} KB (max 1 MB)")
        im = Image.open(io.BytesIO(prev))
        if im.width != im.height or im.width < 512:
            problems.append(f"preview.jpg is {im.width}x{im.height}: must be square, at least 512 px")
    thumb_name = kv.get("preview", "")
    thumb = files.get(thumb_name)
    if thumb_name and thumb is None:
        problems.append(f"info.txt preview {thumb_name} missing")
    elif thumb is not None:
        if len(thumb) > MAX_PREVIEW:
            problems.append(f"{thumb_name} is larger than 1 MB")
        im = Image.open(io.BytesIO(thumb))
        if abs(im.width / im.height - 16 / 9) > 0.03:
            problems.append(f"{thumb_name} is {im.width}x{im.height}: the in-game preview should be 16:9")
    idt = files.get("id.txt")
    if idt is not None and not workshop_id(idt):
        problems.append("id.txt must start with the numeric Steam item id")
    return problems


def workshop_id(data: bytes) -> str | None:
    """The Steam item id from id.txt. The game writes the id on the first line and three
    comment lines after it ("# The first line of this file contains ..."), so only the
    first line is the id (review 16.10.2026: the old check wanted digits only and failed
    every published mod)."""
    lines = data.decode("utf-8", "replace").strip().splitlines()
    first = lines[0].strip() if lines else ""
    return first if first.isdigit() else None


def check_junction(folder: str, mod_dir: str) -> str | None:
    link = os.path.join(os.path.expanduser("~"), "Documents", "Teardown", "mods", folder)
    if not os.path.exists(link):
        return f"note: {link} does not exist (the Mod Manager will not list the mod)"
    if os.path.normcase(os.path.realpath(link)) != os.path.normcase(os.path.realpath(mod_dir)):
        return f"note: {link} does not point to {mod_dir}"
    return None


# --------------------------------------------------------------------------- self-test

def self_test() -> list[str]:
    """The checker must catch planted problems and pass a clean folder."""
    def jpg(w, h):
        b = io.BytesIO()
        Image.new("RGB", (w, h), (90, 90, 90)).save(b, "JPEG")
        return b.getvalue()
    info = b"name = X\nauthor = A\ndescription = d\ntags = Tool\npreview = thumb.jpg\nversion = 2\n"
    clean = {"info.txt": info, "main.lua": b"-- ok\nlocal v = 1.25\n", "preview.jpg": jpg(600, 600), "thumb.jpg": jpg(1024, 576)}
    fails = []
    got = check_files(clean, tokens=[])
    if got:
        fails.append(f"clean folder reported problems: {got}")
    # id.txt exactly as the game writes it on the first publish
    game_id = (b"3817996687\n\n# The first line of this file contains the corresponding Steam Workshop item ID\n"
               b"# It is used when submitting an update and must match one of your items\n"
               b"# You can find the ID of an item in the URL when viewing it in Steam Workshop\n")
    got = check_files(dict(clean, **{"id.txt": game_id}), tokens=[])
    if got:
        fails.append(f"id.txt written by the game reported as a problem: {got}")
    drive = "C:" + "\\" + "Drive" + "\\" + "Someone" + "\\x"
    planted = {
        "path in lua": {"main.lua": ("-- " + drive).encode()},
        "e-mail": {"main.lua": ("-- write to someone" + "@" + "example.org").encode()},
        "ip address": {"main.lua": ("local host = '10." + "1.2.3'").encode()},
        "personal token": {"main.lua": b"-- by Zyxwv"},
        "python file": {"tools.py": b"print(1)"},
        "tests folder": {"tests/scenarios.lua": b"-- test"},
        "wide steam preview": {"preview.jpg": jpg(1024, 576)},
        "missing preview": {"preview.jpg": None},
        "bad tag": {"info.txt": info.replace(b"tags = Tool", b"tags = Weapons")},
        "id.txt without an id": {"id.txt": b"# The first line of this file contains the id\n"},
    }
    for name, change in planted.items():
        f = dict(clean)
        for k, v in change.items():
            if v is None:
                f.pop(k, None)
            else:
                f[k] = v
        if not check_files(f, tokens=[b"zyxwv"]):
            fails.append(f"planted problem not caught: {name}")
    return fails


# --------------------------------------------------------------------------- main

def prepare(root: str) -> list[str]:
    folder = os.path.basename(os.path.abspath(root))
    mod_dir = os.path.join(root, "mod")
    d = MODS.get(folder)
    if d is None:
        return [f"{folder}: no Workshop texts in workshop_data.py"]
    os.makedirs(os.path.join(root, "workshop"), exist_ok=True)
    for lang in ("en", "ru"):
        open(os.path.join(root, "workshop", f"{lang}.txt"), "w", encoding="utf-8", newline="\n").write(bbcode(d, lang))
    update_info(mod_dir, d)
    if not os.path.isfile(os.path.join(mod_dir, "thumb.jpg")):
        return [f"{folder}: thumb.jpg missing (run tools/build_images.py)"]
    square_preview(mod_dir, d["tagline"])
    problems = [f"{folder}: {p}" for p in check_files(read_folder(mod_dir))]
    note = check_junction(folder, mod_dir)
    if note:
        print(f"{folder}: {note}")
    return problems


def main(argv: list[str]) -> int:
    if argv and argv[0] == "--check":
        probs = check_files(read_folder(argv[1]))
        for p in probs:
            print("PROBLEM:", p)
        print("UPLOAD CHECK:", "OK" if not probs else f"{len(probs)} problem(s)")
        return 1 if probs else 0
    if argv and argv[0] == "--all":
        fails = self_test()
        for f in fails:
            print("SELF-TEST FAILED:", f)
        if fails:
            return 1
        print("self-test OK: planted paths, e-mails, IPs, tokens, dev files, bad previews and tags are caught")
        roots = [os.path.join(ROOT, n) for n in sorted(os.listdir(ROOT)) if os.path.isfile(os.path.join(ROOT, n, "mod", "info.txt"))]
    else:
        roots = [argv[0] if argv else os.getcwd()]
    bad = 0
    for r in roots:
        probs = prepare(r)
        for p in probs:
            print("PROBLEM:", p)
        bad += len(probs)
        if not probs:
            print(f"{os.path.basename(os.path.abspath(r))}: upload folder OK")
    print("WORKSHOP:", "OK" if not bad else f"{bad} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
