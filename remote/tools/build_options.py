"""Generate mod/options.lua for the Vehicle Remote."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from options_gen import gen_options  # noqa: E402

ROWS = [
    {"kind": "slider", "key": "range", "label": ("Signal range", "Дальность связи"), "min": 30, "max": 500, "default": 150.0, "fmt": ("%.0f m", "%.0f м"), "step": 10},
    {"kind": "slider", "key": "aimrange", "label": ("Pick-up distance", "Дистанция захвата"), "min": 10, "max": 200, "default": 80.0, "fmt": ("%.0f m", "%.0f м"), "step": 5},
    {"kind": "choice", "key": "follow", "label": ("Chase camera", "Камера за машиной"), "default": True, "choices": [(True, "On at start", "Сразу включена"), (False, "Off at start", "Сразу выключена")]},
    {"kind": "slider", "key": "camdist", "label": ("Camera distance", "Дистанция камеры"), "min": 3, "max": 20, "default": 7.0, "fmt": ("%.0f m", "%.0f м"), "step": 1},
    {"kind": "choice", "key": "freeze", "label": ("Freeze player while driving", "Тело игрока стоит"), "default": True, "choices": [(True, "Yes", "Да"), (False, "No", "Нет")]},
    {"kind": "slider", "key": "sens", "label": ("Mouse sensitivity", "Чувствительность мыши"), "min": 0.2, "max": 3, "default": 1.0, "fmt": ("x%.1f", "x%.1f"), "step": 0.1},
]

if __name__ == "__main__":
    gen_options(os.path.join(HERE, "..", "mod", "options.lua"), ("Vehicle Remote", "Радиоуправление"),
                ("Drive any car from a distance", "Управляйте любой машиной издалека"), ROWS, accent=(1.0, 0.35, 0.3))
    print("wrote options.lua")
