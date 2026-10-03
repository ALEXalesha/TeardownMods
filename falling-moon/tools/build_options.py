"""Generate mod/options.lua for the Falling Moon."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from options_gen import gen_options  # noqa: E402

ROWS = [
    {"kind": "slider", "key": "duration", "label": ("Time until impact", "Время до удара"), "min": 60, "max": 300, "default": 120.0, "fmt": ("%.0f s", "%.0f с"), "step": 10},
    {"kind": "slider", "key": "radius", "label": ("Shockwave radius", "Радиус ударной волны"), "min": 50, "max": 300, "default": 150.0, "fmt": ("%.0f m", "%.0f м"), "step": 10},
    {"kind": "choice", "key": "damage", "label": ("Damage to players", "Урон игрокам"), "default": 1, "int": True, "choices": [(0, "Off", "Нет"), (1, "Normal", "Обычный"), (2, "Deadly", "Смертельный")]},
    {"kind": "choice", "key": "destruction", "label": ("Destruction", "Разрушения"), "default": 3, "int": True, "choices": [(1, "Strong", "Сильные"), (2, "Heavy", "Тяжёлые"), (3, "Total", "Полные")]},
    {"kind": "choice", "key": "moonsize", "label": ("Moon size", "Размер луны"), "default": 45, "int": True, "choices": [(30, "30 m", "30 м"), (45, "45 m", "45 м"), (60, "60 m", "60 м")]},
    {"kind": "choice", "key": "fire", "label": ("Fires", "Пожары"), "default": True, "choices": [(True, "On", "Вкл"), (False, "Off", "Выкл")]},
    {"kind": "slider", "key": "tint", "label": ("Red sky", "Красное небо"), "min": 0, "max": 1, "default": 0.8, "fmt": ("%.1f", "%.1f"), "step": 0.1},
    {"kind": "choice", "key": "tremors", "label": ("Tremors and wind", "Толчки и ветер"), "default": True, "choices": [(True, "On", "Вкл"), (False, "Off", "Выкл")]},
    {"kind": "choice", "key": "countdown", "label": ("Countdown", "Обратный отсчёт"), "default": True, "choices": [(True, "Show", "Показывать"), (False, "Hide", "Скрыть")]},
]

if __name__ == "__main__":
    gen_options(os.path.join(HERE, "..", "mod", "options.lua"), ("Falling Moon", "Падающая луна"),
                ("Settings apply to the next moon", "Настройки действуют со следующей луны"), ROWS, accent=(1.0, 0.45, 0.3))
    print("wrote options.lua")
