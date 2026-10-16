"""Every keyboard key of every mod in this repository, and the law that no two of them clash.

Independent review 16.10.2026: with two mods on, one key did two things (G = Gravity Change and
Mover's clone, T = Time Slow's option and Mover's freeze, J = Gravity's option and Time Slow's
speed). This table is the single list of keys; the law checks it against the code of every mod
and against the game's own keys.

Where a key works ("ctx"):
  global  - always, whatever is in the hands (Gravity Change, Time Slow, replay mod)
  tool    - only while this mod's tool is in the hands
  replay  - while replay mod shows a replay; the replay puts the owner's tool away (SetPlayerTool
            "none"), so no tool key works then (law replay mod/tests/replay_tool_law.lua)
  drone   - while flying the Camera Drone; it ends when the drone tool is put away
  remote  - while driving a car with the Vehicle Remote; it ends when the remote is put away
            (law remote/tests/tool_switch_law.lua)
Only one tool is in the hands at a time, so "tool", "replay", "drone" and "remote" keys of
different mods never act together. A global key acts together with everything, so it must not be
used anywhere else, and every choice of a global key in the options must be free too (any
combination of settings must work).

Run: python keymap.py            the law (exit code 1 on a problem) and the self-test
     python keymap.py --readme   rewrite the key tables in README.md / README.ru.md
"""
from __future__ import annotations

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

# --------------------------------------------------------------------------- the game's keys

# data/input_settings.xml of the game (keyboard bindings) and data/ui/hud.lua (F4, F6-F8), plus
# quick save / quick load. A mod must never use these as raw keys.
GAME_KEYS = {
    "w": "move forward", "a": "move left", "s": "move back", "d": "move right", "space": "jump",
    "ctrl": "crouch", "shift": "scoreboard", "e": "interact", "f": "flashlight", "c": "camera view",
    "tab": "map", "esc": "pause", "f4": "HUD", "f5": "quick save", "f6": "HUD", "f7": "HUD",
    "f8": "HUD", "f9": "quick load",
}
# used by the game only in menus or the photo mode, never while playing: allowed for a mod's tool or
# replay keys, but not for a global key
GAME_MENU_KEYS = {
    "uparrow": "menu", "downarrow": "menu", "leftarrow": "menu", "rightarrow": "menu",
    "pgup": "menu", "pgdown": "menu", "return": "menu", "mmb": "photo mode and spawn menu",
}
# data/script/creativemode.lua: only with the creative mode's own tool, so a mod's tool key may use
# them, a global key may not
CREATIVE_KEYS = {"q": "up", "z": "down", "m": "brush", "alt": "pick", "delete": "delete", "1": "mode", "2": "mode", "3": "mode"}

# game actions are read by name and follow the player's own key bindings; they are not raw keys
ACTIONS = {"usetool", "grab", "jump", "crouch", "up", "down", "left", "right", "interact", "flashlight",
           "map", "pause", "camerax", "cameray", "mousewheel", "mousedx", "mousedy", "handbrake",
           "vehicleraise", "vehiclelower", "vehicleaction", "zoom", "scoreboard", "camera_view"}

LABEL = {"mmb": ("Middle mouse", "Средняя кнопка мыши"), "uparrow": ("Up", "Вверх"), "downarrow": ("Down", "Вниз"),
         "leftarrow": ("Left", "Влево"), "rightarrow": ("Right", "Вправо"), "space": ("Space", "Пробел"),
         "ctrl": ("Ctrl", "Ctrl"), "shift": ("Shift", "Shift"), "tab": ("Tab", "Tab"), "esc": ("Esc", "Esc")}

CTX = {
    "global": ("always", "всегда"),
    "tool": ("with the tool in hand", "с инструментом в руках"),
    "replay": ("in the replay", "в повторе"),
    "drone": ("flying the drone", "в полёте дрона"),
    "remote": ("driving a car", "за рулём машины"),
    "aim": ("aiming at the machine, any tool", "наведя на машину, с любым инструментом"),
}

# --------------------------------------------------------------------------- the table

def K(ctx, keys, en, ru, option=None, default=None, code="literal"):
    """keys: the key, or for an option every choice (the first one is the default)."""
    return {"ctx": ctx, "keys": list(keys), "en": en, "ru": ru, "option": option,
            "default": default or keys[0], "code": code}


KEYMAP = {
    "gravity": [
        K("global", ["g", "k"], "next gravity; hold 0.8 s: back to Earth", "следующая гравитация; держать 0,8 с: Земля", option="key"),
    ],
    "time-slow": [
        K("global", ["h", "y", "mmb"], "slow motion (hold or toggle)", "замедление (держать или нажать-отжать)", option="key"),
        K("global", ["j", "i"], "speed x0.5 / x0.25 / x0.1", "скорость x0,5 / x0,25 / x0,1", option="speedkey"),
    ],
    "replay mod": [
        K("global", ["o", "l"], "open / close the replay", "открыть / закрыть повтор", option="key"),
        K("replay", ["p"], "pause / play", "пауза / воспроизведение"),
        K("replay", ["leftarrow", "rightarrow"], "scrub back / forward", "перемотка назад / вперёд"),
        K("replay", ["uparrow", "downarrow"], "speed", "скорость"),
        K("replay", ["v"], "camera", "камера"),
        K("replay", ["r"], "restart", "с начала"),
    ],
    "mover": [
        K("tool", ["q", "r"], "rotate", "поворот"),
        K("tool", ["z", "x"], "tilt", "наклон"),
        K("tool", ["v", "b"], "roll", "крен"),
        K("tool", ["t"], "freeze / unfreeze", "заморозить / разморозить"),
        K("tool", ["p"], "clone", "клонировать"),
        K("tool", ["n", "m"], "scale x0.5 / x2", "масштаб x0,5 / x2"),
        K("tool", ["u"], "undo", "отменить"),
    ],
    "drone": [
        K("tool", ["r"], "pick the drone up (on foot, within 4 m)", "забрать дрон (пешком, ближе 4 м)"),
        K("drone", ["q"], "back to your body (the drone keeps hovering)", "вернуться в тело (дрон висит)"),
        K("drone", ["p"], "photo mode", "фоторежим"),
    ],
    "remote": [
        K("remote", ["q"], "let go", "отпустить"),
        K("remote", ["v"], "chase camera on / off", "камера сзади вкл / выкл"),
    ],
    "portal-gun": [K("tool", ["r"], "close both portals", "закрыть оба портала")],
    "trampoline-floor": [K("tool", ["r"], "whole ground bounces on / off", "вся земля прыгает вкл / выкл")],
    "volcano": [K("tool", ["r"], "remove the cones", "убрать конусы")],
    "catapult": [
        K("tool", ["r"], "remove all catapults", "убрать все катапульты"),
        K("tool", ["q"], "fire", "выстрел"),
        K("tool", ["z", "x"], "turn", "поворот"),
        K("tool", ["v", "b"], "angle", "угол"),
        K("tool", ["1", "2", "3", "4"], "load", "снаряд", code="loop"),
        # the game's own "interact" action (E unless rebound) on the catapult itself, like a door
        K("aim", ["e"], "fire (the game's interact)", "выстрел (действие игры «использовать»)", code="action"),
    ],
}
# mods with mouse buttons only (LMB / RMB through the game's usetool / grab)
MOUSE_ONLY = ["cutter", "earthquake", "falling-moon", "singularity-grenade", "telekinesis", "tornado", "tsunami"]

# --------------------------------------------------------------------------- reading the code

RAW = re.compile(r"^([a-z0-9]|f\d{1,2}|uparrow|downarrow|leftarrow|rightarrow|mmb|lmb|rmb|esc|tab|return|space|shift|ctrl|alt|delete|home|insert|backspace|pgup|pgdown)$")
CALL = re.compile(r"Input(?:Pressed|Down|Released)\(\s*\"([^\"]+)\"")
TUPLE = re.compile(r"\{\s*\"([a-z0-9])\"\s*,\s*-?\d")          # mover: { "q", 1, -1 }
OPTION_ROW = re.compile(r"\{ kind = \"choice\", key = \"(\w+)\".*?default = \"([^\"]*)\", choices = \{(.*?)\} \},?\s*$", re.M)
CHOICE = re.compile(r"\{ \"([^\"]*)\", \"([^\"]*)\", \"([^\"]*)\" \}")


def is_raw(name: str) -> bool:
    return bool(RAW.match(name)) and name not in ACTIONS


def read_sources(root: str = ROOT) -> dict:
    out = {}
    for m in sorted(os.listdir(root)):
        main = os.path.join(root, m, "mod", "main.lua")
        if not os.path.isfile(main):
            continue
        opt = os.path.join(root, m, "mod", "options.lua")
        out[m] = {"main": open(main, encoding="utf-8").read(),
                  "options": open(opt, encoding="utf-8").read() if os.path.isfile(opt) else ""}
    return out


def code_keys(src: str) -> set:
    found = {k for k in CALL.findall(src) if is_raw(k)}
    found |= set(TUPLE.findall(src))
    return found


def option_rows(options_src: str) -> dict:
    rows = {}
    for key, default, body in OPTION_ROW.findall(options_src):
        rows[key] = {"default": default, "choices": [c[0] for c in CHOICE.findall(body)]}
    return rows


# --------------------------------------------------------------------------- the law

def check(keymap: dict, sources: dict, mouse_only=MOUSE_ONLY) -> list:
    problems = []
    # "action" rows are the game's own actions (read by name, they follow the player's bindings)
    entries = [(m, e) for m, lst in keymap.items() for e in lst if e["code"] != "action"]
    globals_ = [(m, e, k) for m, e in entries if e["ctx"] == "global" for k in e["keys"]]
    others = [(m, e, k) for m, e in entries if e["ctx"] != "global" for k in e["keys"]]

    # 1. a global key (every choice of it) is used nowhere else
    seen = {}
    for m, e, k in globals_:
        if k in seen:
            problems.append(f"global key {k.upper()}: {seen[k]} and {m} ({e['en']})")
        seen[k] = f"{m} ({e['en']})"
    for m, e, k in others:
        if k in seen:
            problems.append(f"global key {k.upper()} of {seen[k]} also does '{e['en']}' in {m} ({e['ctx']})")
    # 2. game keys
    for m, e, k in globals_ + others:
        if k in GAME_KEYS:
            problems.append(f"{m}: {k.upper()} ({e['en']}) is the game's {GAME_KEYS[k]}")
    for m, e, k in globals_:
        # the middle button: the game uses it only in the photo mode and the sandbox spawn menu, where
        # the global mods do nothing (they check game.paused); Time Slow offered it before 16.10
        if k == "mmb":
            continue
        if k in GAME_MENU_KEYS or k in CREATIVE_KEYS:
            problems.append(f"{m}: global {k.upper()} is also the game's {GAME_MENU_KEYS.get(k) or 'creative mode ' + CREATIVE_KEYS[k]}")
    # 3. inside one mod and one context every key does one thing
    per = {}
    for m, e, k in others:
        key = (m, e["ctx"], k)
        if key in per:
            problems.append(f"{m}: {k.upper()} does '{per[key]}' and '{e['en']}' ({e['ctx']})")
        per[key] = e["en"]
    # 4. the table matches the code
    for m, src in sources.items():
        lst = keymap.get(m, [])
        if not lst and m not in mouse_only:
            problems.append(f"{m}: not in the key table")
        declared = {k for e in lst if not e["option"] and e["code"] != "action" for k in e["keys"]}
        found = code_keys(src["main"])
        for k in sorted(found - declared):
            problems.append(f"{m}: main.lua reads key {k.upper()}, which is not in the key table")
        for e in lst:
            if e["option"] or e["code"] in ("loop", "action"):
                continue
            for k in e["keys"]:
                if f'"{k}"' not in src["main"]:
                    problems.append(f"{m}: key {k.upper()} ({e['en']}) is in the table but not in main.lua")
        rows = option_rows(src["options"])
        for e in lst:
            if not e["option"]:
                continue
            row = rows.get(e["option"])
            if row is None:
                problems.append(f"{m}: no options row '{e['option']}' for {e['en']}")
                continue
            if row["choices"] != e["keys"] or row["default"] != e["default"]:
                problems.append(f"{m}: options row '{e['option']}' offers {row['choices']} (default {row['default']}), table says {e['keys']} (default {e['default']})")
            if not re.search(r'getS\("' + e["option"] + r'", "' + e["default"] + r'"\)', src["main"]):
                problems.append(f"{m}: main.lua does not read savegame.mod.{e['option']} with default {e['default']}")
    for m in keymap:
        if m not in sources:
            problems.append(f"{m}: in the key table but no such mod")
    return problems


def self_test() -> list:
    """Plant each kind of problem; every one must be caught."""
    import copy
    src = read_sources()
    fails = []

    def expect(name, km, s=None, word=None):
        p = check(km, s or src)
        if not p or (word and not any(word in x for x in p)):
            fails.append(name)

    km = copy.deepcopy(KEYMAP); km["gravity"][0]["keys"] = ["g", "j"]
    expect("two global keys", km, word="global key J")
    km = copy.deepcopy(KEYMAP); km["mover"][4]["keys"] = ["g"]
    s = copy.deepcopy(src); s["mover"]["main"] += '\nInputPressed("g")'
    expect("global key used by a tool", km, s, "global key G")
    km = copy.deepcopy(KEYMAP); km["portal-gun"][0]["keys"] = ["f"]
    s = copy.deepcopy(src); s["portal-gun"]["main"] += '\nInputPressed("f")'
    expect("game key", km, s, "flashlight")
    km = copy.deepcopy(KEYMAP); km["time-slow"][0]["keys"] = ["h", "y", "q"]
    expect("global creative key", km, word="creative")
    s = copy.deepcopy(src); s["volcano"]["main"] += '\nif InputPressed("n") then end'
    expect("key read in code but not listed", KEYMAP, s, "not in the key table")
    km = copy.deepcopy(KEYMAP); km["mover"].append(K("tool", ["q"], "x", "x"))
    expect("one key, two actions in a tool", km, word="does")
    s = copy.deepcopy(src); s["gravity"]["options"] = s["gravity"]["options"].replace('{ "k", "K", "K" }', '{ "j", "J", "J" }')
    expect("options offer another key", KEYMAP, s, "options row")
    return fails


# --------------------------------------------------------------------------- README tables

def label(k: str, ru: bool) -> str:
    if k in LABEL:
        return LABEL[k][1 if ru else 0]
    return k.upper()


def markdown(ru: bool) -> str:
    title = {m: m for m in KEYMAP}
    try:
        sys.path.insert(0, HERE)
        from workshop_data import MODS
        for m in list(KEYMAP) + MOUSE_ONLY:
            if m in MODS:
                title[m] = MODS[m]["title_ru" if ru else "title"]
    except Exception:
        pass
    head = ("| Мод | Клавиша | Где действует | Что делает |\n|---|---|---|---|" if ru else
            "| Mod | Key | Where it works | What it does |\n|---|---|---|---|")
    rows = []
    for m in sorted(KEYMAP):
        for e in KEYMAP[m]:
            keys = " / ".join(label(k, ru) for k in e["keys"])
            if e["option"]:
                keys = (f"{label(e['default'], ru)} (на выбор: {keys})" if ru else f"{label(e['default'], ru)} (choice: {keys})")
            rows.append(f"| {title.get(m, m)} | {keys} | {CTX[e['ctx']][1 if ru else 0]} | {e['ru' if ru else 'en']} |")
    mouse = ", ".join(title.get(m, m) for m in MOUSE_ONLY)
    game = ", ".join(label(k, ru) for k in GAME_KEYS)
    if ru:
        tail = (f"\nТолько мышь (ЛКМ / ПКМ): {mouse}.\n\n"
                f"Клавиши игры, которые моды не занимают своими действиями: {game}; в творческом режиме ещё Q, Z, M, Alt, Delete, 1-3. "
                "E у катапульты - это само действие игры «использовать», наведя на машину.\n"
                "Клавиши «всегда» не повторяются нигде: ни в другом моде, ни среди вариантов в настройках. Клавиши "
                "«с инструментом», «в повторе», «в полёте дрона» и «за рулём» могут совпадать у разных модов: в руках "
                "один инструмент, повтор убирает инструмент из рук, полёт дрона и руль заканчиваются, если убрать "
                "дрон или пульт. Проверяет закон `_shared/tdlib/keymap.py`.")
    else:
        tail = (f"\nMouse only (LMB / RMB): {mouse}.\n\n"
                f"Game keys the mods never use for their own actions: {game}; in the creative mode also Q, Z, M, Alt, Delete, 1-3. "
                "E on the catapult is the game's own interact action, aimed at the machine.\n"
                "\"Always\" keys are not used anywhere else: not by another mod and not among the choices in the "
                "options. Keys \"with the tool in hand\", \"in the replay\", \"flying the drone\" and \"driving a car\" "
                "may repeat between mods: only one tool is in the hands, the replay puts the tool away, the drone flight "
                "and the remote driving end when the drone or the remote is put away. Checked by the law "
                "`_shared/tdlib/keymap.py`.")
    return head + "\n" + "\n".join(rows) + "\n" + tail + "\n"


def stale_readmes() -> list:
    """README key tables that differ from this table (run --readme after a change)."""
    out = []
    for name, ru in (("README.md", False), ("README.ru.md", True)):
        text = open(os.path.join(ROOT, name), encoding="utf-8").read().replace("\r\n", "\n")
        m = re.search(r"<!-- keys -->\n(.*?)<!-- /keys -->", text, re.S)
        if not m or m.group(1) != markdown(ru):
            out.append(f"{name}: the key table is not up to date (python _shared/tdlib/keymap.py --readme)")
    return out


def write_readmes() -> None:
    for name, ru in (("README.md", False), ("README.ru.md", True)):
        p = os.path.join(ROOT, name)
        raw = open(p, "rb").read()
        crlf = b"\r\n" in raw
        text = raw.decode("utf-8").replace("\r\n", "\n")
        block = "<!-- keys -->\n" + markdown(ru) + "<!-- /keys -->"
        if "<!-- keys -->" in text:
            text = re.sub(r"<!-- keys -->.*?<!-- /keys -->", lambda _: block, text, flags=re.S)
        else:
            raise SystemExit(f"{name}: no <!-- keys --> marker")
        if crlf:
            text = text.replace("\n", "\r\n")
        open(p, "wb").write(text.encode("utf-8"))


def main(argv) -> int:
    if argv and argv[0] == "--readme":
        write_readmes()
        print("key tables written")
        return 0
    fails = self_test()
    print("key law self-test:", "OK" if not fails else "FAIL " + ", ".join(fails))
    problems = check(KEYMAP, read_sources()) + stale_readmes()
    for p in problems:
        print("KEY CLASH:", p)
    print("KEY LAW:", "OK" if not problems else f"{len(problems)} problem(s)")
    return 1 if problems or fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
