"""Generate mod/options.lua for Telekinesis."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from options_gen import gen_options  # noqa: E402

ROWS = [
    {"kind": "slider", "key": "radius", "label": ("Pick-up radius", "Радиус захвата"), "min": 1, "max": 8, "default": 3.0, "fmt": ("%.1f m", "%.1f м"), "step": 0.5},
    {"kind": "slider", "key": "maxbodies", "label": ("Max objects", "Макс. предметов"), "min": 1, "max": 20, "default": 8.0, "fmt": ("%.0f", "%.0f"), "step": 1},
    {"kind": "slider", "key": "masslimit", "label": ("Heaviest object", "Самый тяжёлый предмет"), "min": 10, "max": 1000, "default": 200.0, "fmt": ("%.0f kg", "%.0f кг"), "step": 10},
    {"kind": "slider", "key": "power", "label": ("Throw power", "Сила броска"), "min": 0.3, "max": 3, "default": 1.0, "fmt": ("x%.1f", "x%.1f"), "step": 0.1},
    {"kind": "slider", "key": "reach", "label": ("Reach", "Дальность"), "min": 5, "max": 100, "default": 40.0, "fmt": ("%.0f m", "%.0f м"), "step": 5},
    {"kind": "choice", "key": "energy", "label": ("Energy meter", "Шкала энергии"), "default": True, "choices": [(True, "On", "Вкл"), (False, "Off (unlimited)", "Выкл (без ограничений)")]},
    {"kind": "slider", "key": "capacity", "label": ("Energy lasts", "Энергии хватает на"), "min": 5, "max": 60, "default": 15.0, "fmt": ("%.0f s", "%.0f с"), "step": 1},
]

if __name__ == "__main__":
    gen_options(os.path.join(HERE, "..", "mod", "options.lua"), ("Telekinesis", "Телекинез"),
                ("Lift, swirl, throw", "Поднять, закрутить, бросить"), ROWS, accent=(0.7, 0.45, 1.0))
    print("wrote options.lua")
