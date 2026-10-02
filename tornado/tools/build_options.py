"""Generate mod/options.lua for the Tornado."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from options_gen import gen_options  # noqa: E402

YN = [(True, "Yes", "Да"), (False, "No", "Нет")]
ROWS = [
    {"kind": "slider", "key": "strength", "label": ("Strength", "Сила"), "min": 0.3, "max": 3, "default": 1.0, "fmt": ("x%.1f", "x%.1f"), "step": 0.1},
    {"kind": "slider", "key": "size", "label": ("Size (top radius)", "Размер (радиус вверху)"), "min": 4, "max": 20, "default": 8.0, "fmt": ("%.0f m", "%.0f м"), "step": 1},
    {"kind": "slider", "key": "duration", "label": ("Lifetime", "Время жизни"), "min": 10, "max": 180, "default": 40.0, "fmt": ("%.0f s", "%.0f с"), "step": 5},
    {"kind": "slider", "key": "speed", "label": ("Travel speed", "Скорость движения"), "min": 1, "max": 12, "default": 4.0, "fmt": ("%.0f m/s", "%.0f м/с"), "step": 1},
    {"kind": "choice", "key": "follow", "label": ("Movement", "Движение"), "default": False, "choices": [(False, "Wanders on its own", "Бродит сам"), (True, "Follows your aim", "Идёт за прицелом")]},
    {"kind": "choice", "key": "vehicles", "label": ("Lifts vehicles", "Поднимает машины"), "default": True, "choices": YN},
    {"kind": "choice", "key": "player", "label": ("Lifts the player", "Поднимает игрока"), "default": True, "choices": YN},
    {"kind": "choice", "key": "damage", "label": ("Tears buildings", "Рвёт постройки"), "default": True, "choices": YN},
]

if __name__ == "__main__":
    gen_options(os.path.join(HERE, "..", "mod", "options.lua"), ("Tornado", "Торнадо"),
                ("Settings apply to the next tornado", "Настройки действуют со следующего торнадо"), ROWS, accent=(0.6, 0.75, 0.9))
    print("wrote options.lua")
