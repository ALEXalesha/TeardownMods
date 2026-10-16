"""Generate mod/options.lua for the Mover."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from options_gen import gen_options  # noqa: E402

ROWS = [
    {"kind": "slider", "key": "maxdist", "label": ("Max distance", "Макс. дальность"), "min": 5, "max": 100, "default": 40.0, "fmt": ("%.0f m", "%.0f м"), "step": 1},
    {"kind": "slider", "key": "speed", "label": ("Move speed", "Скорость переноса"), "min": 5, "max": 40, "default": 20.0, "fmt": ("%.0f m/s", "%.0f м/с"), "step": 1},
    {"kind": "choice", "key": "possnap", "label": ("Position snap", "Привязка к сетке"), "default": 0.0,
     "choices": [(0.0, "Off", "Нет"), (0.1, "0.1 m", "0,1 м"), (0.25, "0.25 m", "0,25 м"), (0.5, "0.5 m", "0,5 м"), (1.0, "1 m", "1 м")]},
    {"kind": "choice", "key": "rotsnap", "label": ("Rotation snap", "Шаг поворота"), "default": 0.0,
     "choices": [(0.0, "Off (smooth)", "Нет (плавно)"), (15.0, "15°", "15°"), (45.0, "45°", "45°"), (90.0, "90°", "90°")]},
    {"kind": "slider", "key": "rotspeed", "label": ("Rotation speed", "Скорость поворота"), "min": 30, "max": 360, "default": 90.0, "fmt": ("%.0f°/s", "%.0f°/с"), "step": 5},
    {"kind": "choice", "key": "clone", "label": ("Cloning (P)", "Клонирование (P)"), "default": True, "choices": [(True, "On", "Вкл"), (False, "Off", "Выкл")]},
    {"kind": "choice", "key": "scale", "label": ("Scaling (N/M)", "Масштаб (N/M)"), "default": True, "choices": [(True, "On (experimental)", "Вкл (опытный)"), (False, "Off", "Выкл")]},
    {"kind": "choice", "key": "help", "label": ("Controls panel", "Подсказка клавиш"), "default": True, "choices": [(True, "Show", "Показывать"), (False, "Hide", "Скрыть")]},
]

if __name__ == "__main__":
    gen_options(os.path.join(HERE, "..", "mod", "options.lua"), ("Mover", "Перемещатель"),
                ("Grab, rotate, freeze, clone", "Хватай, крути, замораживай, клонируй"), ROWS, accent=(0.3, 1.0, 1.0))
    print("wrote options.lua")
