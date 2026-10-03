"""Generate mod/options.lua for the Volcano."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from options_gen import gen_options  # noqa: E402

YN = [(True, "On", "Вкл"), (False, "Off", "Выкл")]
ROWS = [
    {"kind": "choice", "key": "size", "label": ("Size", "Размер"), "default": 2, "int": True, "choices": [(1, "Small (22 m)", "Малый (22 м)"), (2, "Medium (29 m)", "Средний (29 м)"), (3, "Large (44 m)", "Большой (44 м)")]},
    {"kind": "slider", "key": "strength", "label": ("Eruption strength", "Сила извержения"), "min": 0.5, "max": 2, "default": 1.0, "fmt": ("x%.1f", "x%.1f"), "step": 0.1},
    {"kind": "slider", "key": "duration", "label": ("Eruption length", "Длительность извержения"), "min": 20, "max": 120, "default": 45.0, "fmt": ("%.0f s", "%.0f с"), "step": 5},
    {"kind": "choice", "key": "fire", "label": ("Fires", "Пожары"), "default": True, "choices": YN},
    {"kind": "choice", "key": "debug", "label": ("Debug line (for testing)", "Строка отладки (для проверки)"), "default": True, "choices": YN},
    {"kind": "choice", "key": "ash", "label": ("Ash fall", "Пепел"), "default": True, "choices": YN},
]

if __name__ == "__main__":
    gen_options(os.path.join(HERE, "..", "mod", "options.lua"), ("Volcano", "Вулкан"),
                ("Settings apply to the next volcano", "Настройки действуют со следующего вулкана"), ROWS, accent=(1.0, 0.45, 0.15))
    print("wrote options.lua")
