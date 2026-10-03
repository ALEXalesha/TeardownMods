"""Generate mod/options.lua for the Tsunami."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from options_gen import gen_options  # noqa: E402

ROWS = [
    {"kind": "slider", "key": "height", "label": ("Wave height", "Высота волны"), "min": 3, "max": 20, "default": 9.0, "fmt": ("%.0f m", "%.0f м"), "step": 1},
    {"kind": "slider", "key": "speed", "label": ("Wave speed", "Скорость волны"), "min": 8, "max": 30, "default": 14.0, "fmt": ("%.0f m/s", "%.0f м/с"), "step": 1},
    {"kind": "slider", "key": "flood", "label": ("Flood level behind it", "Уровень затопления за ней"), "min": 0, "max": 4, "default": 1.5, "fmt": ("%.1f m", "%.1f м"), "step": 0.5},
    {"kind": "slider", "key": "power", "label": ("Damage to weak structures", "Разрушение слабых построек"), "min": 0, "max": 2, "default": 1.0, "fmt": ("x%.1f", "x%.1f"), "step": 0.1},
    {"kind": "choice", "key": "siren", "label": ("Warning siren", "Сирена"), "default": True, "choices": [(True, "On", "Вкл"), (False, "Off", "Выкл")]},
]

if __name__ == "__main__":
    gen_options(os.path.join(HERE, "..", "mod", "options.lua"), ("Tsunami", "Цунами"),
                ("Settings apply to the next wave", "Настройки действуют со следующей волны"), ROWS, accent=(0.3, 0.7, 1.0))
    print("wrote options.lua")
