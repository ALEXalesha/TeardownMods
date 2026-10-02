"""Generate mod/options.lua for the Earthquake mod."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from options_gen import gen_options  # noqa: E402

ROWS = [
    {"kind": "slider", "key": "duration", "label": ("Duration", "Длительность"), "min": 5, "max": 60, "default": 15.0,
     "fmt": ("%.0f s", "%.0f с"), "step": 1},
    {"kind": "choice", "key": "preset", "label": ("Starting preset", "Сила по умолчанию"), "default": 3, "int": True,
     "choices": [(1, "Weak", "Слабое"), (2, "Moderate", "Умеренное"), (3, "Strong", "Сильное"),
                 (4, "Severe", "Разрушительное"), (5, "Catastrophic", "Катастрофическое")]},
    {"kind": "slider", "key": "radius", "label": ("Radius", "Радиус"), "min": 20, "max": 150, "default": 60.0,
     "fmt": ("%.0f m", "%.0f м"), "step": 5},
    {"kind": "choice", "key": "aftershocks", "label": ("Aftershocks", "Афтершоки"), "default": True,
     "choices": [(True, "Yes", "Да"), (False, "No", "Нет")]},
    {"kind": "choice", "key": "damage", "label": ("Structural damage", "Разрушение построек"), "default": True,
     "choices": [(True, "Yes", "Да"), (False, "No (shaking only)", "Нет (только тряска)")]},
    {"kind": "slider", "key": "shake", "label": ("Camera shake", "Тряска камеры"), "min": 0, "max": 2, "default": 1.0,
     "fmt": ("x%.1f", "x%.1f"), "step": 0.1},
    {"kind": "choice", "key": "atplayer", "label": ("Epicentre", "Эпицентр"), "default": False,
     "choices": [(False, "Aim point", "Точка прицела"), (True, "Under the player", "Под игроком")]},
]

if __name__ == "__main__":
    gen_options(os.path.join(HERE, "..", "mod", "options.lua"), ("Earthquake", "Землетрясение"),
                ("Settings apply to the next quake", "Настройки действуют со следующего толчка"), ROWS,
                accent=(1.0, 0.75, 0.25))
    print("wrote options.lua")
