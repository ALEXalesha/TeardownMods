"""Generate mod/options.lua for the Portal Gun."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from options_gen import gen_options  # noqa: E402

ROWS = [
    {"kind": "slider", "key": "range", "label": ("Range", "Дальность"), "min": 20, "max": 200, "default": 100.0, "fmt": ("%.0f m", "%.0f м"), "step": 5},
    {"kind": "choice", "key": "size", "label": ("Portal size", "Размер портала"), "default": 2, "int": True,
     "choices": [(1, "Small", "Маленький"), (2, "Normal", "Обычный"), (3, "Large", "Большой")]},
    {"kind": "choice", "key": "bodies", "label": ("Objects pass through", "Предметы проходят"), "default": True, "choices": [(True, "Yes", "Да"), (False, "No", "Нет")]},
    {"kind": "slider", "key": "masslimit", "label": ("Heaviest object", "Самый тяжёлый предмет"), "min": 50, "max": 3000, "default": 500.0, "fmt": ("%.0f kg", "%.0f кг"), "step": 50},
    {"kind": "choice", "key": "dynamic", "label": ("Portals on moving objects", "Порталы на подвижных предметах"), "default": False, "choices": [(False, "No", "Нет"), (True, "Yes (follow them)", "Да (едут с ними)")]},
    {"kind": "slider", "key": "hum", "label": ("Portal hum volume", "Гул портала"), "min": 0, "max": 1, "default": 0.5, "fmt": ("%.1f", "%.1f"), "step": 0.1},
]

if __name__ == "__main__":
    gen_options(os.path.join(HERE, "..", "mod", "options.lua"), ("Portal Gun", "Портальная пушка"),
                ("Blue in, orange out", "Вошёл в синий, вышел из оранжевого"), ROWS, accent=(0.3, 0.65, 1.0))
    print("wrote options.lua")
