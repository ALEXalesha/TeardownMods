"""Generate mod/options.lua for the Catapult."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from options_gen import gen_options  # noqa: E402

YN = [(True, "On", "Вкл"), (False, "Off", "Выкл")]
ROWS = [
    {"kind": "choice", "key": "ammo", "label": ("Ammo at start", "Снаряд по умолчанию"), "default": 1, "int": True, "choices": [(1, "Boulder", "Валун"), (2, "Explosive barrel", "Бочка со взрывчаткой"), (3, "Car", "Машина"), (4, "Crates", "Ящики")]},
    {"kind": "choice", "key": "reload", "label": ("Reload automatically", "Заряжать автоматически"), "default": True, "choices": YN},
    {"kind": "slider", "key": "damage", "label": ("Impact damage", "Сила попадания"), "min": 0.25, "max": 2, "default": 1.0, "fmt": ("x%.2f", "x%.2f"), "step": 0.05},
    {"kind": "choice", "key": "falldamage", "label": ("Fall damage for a launched player", "Урон от падения для запущенного игрока"), "default": False, "choices": [(False, "Off", "Выкл"), (True, "On", "Вкл")]},
    {"kind": "choice", "key": "debug", "label": ("Debug line (for testing)", "Строка отладки (для проверки)"), "default": True, "choices": YN},
    {"kind": "choice", "key": "arc", "label": ("Arc preview", "Предпросмотр траектории"), "default": True, "choices": YN},
]

if __name__ == "__main__":
    gen_options(os.path.join(HERE, "..", "mod", "options.lua"), ("Catapult", "Катапульта"),
                ("Settings apply to the next shot", "Настройки действуют со следующего выстрела"), ROWS, accent=(0.9, 0.6, 0.25))
    print("wrote options.lua")
