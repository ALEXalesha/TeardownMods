"""Generate mod/options.lua for Time Slow."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from options_gen import gen_options  # noqa: E402

ROWS = [
    {"kind": "choice", "key": "key", "label": ("Slow motion key", "Клавиша замедления"), "default": "h",
     "choices": [("h", "H", "H"), ("y", "Y", "Y"), ("t", "T", "T"), ("mmb", "Middle mouse", "Средняя кнопка мыши")]},
    {"kind": "choice", "key": "toggle", "label": ("Mode", "Режим"), "default": False,
     "choices": [(False, "Hold", "Удерживать"), (True, "Toggle", "Нажать / отжать")]},
    {"kind": "choice", "key": "preset", "label": ("Starting speed", "Скорость при старте"), "default": 2, "int": True,
     "choices": [(1, "x0.5", "x0,5"), (2, "x0.25", "x0,25"), (3, "x0.1", "x0,1")]},
    {"kind": "slider", "key": "ramp", "label": ("Ramp time", "Плавность входа"), "min": 0.05, "max": 1.5, "default": 0.35, "fmt": ("%.2f s", "%.2f с"), "step": 0.05},
    {"kind": "choice", "key": "energy", "label": ("Energy meter", "Шкала энергии"), "default": True, "choices": [(True, "On", "Вкл"), (False, "Off (unlimited)", "Выкл (без ограничений)")]},
    {"kind": "slider", "key": "capacity", "label": ("Energy lasts", "Энергии хватает на"), "min": 2, "max": 60, "default": 8.0, "fmt": ("%.0f s", "%.0f с"), "step": 1},
    {"kind": "slider", "key": "recharge", "label": ("Full recharge", "Полная перезарядка"), "min": 2, "max": 60, "default": 12.0, "fmt": ("%.0f s", "%.0f с"), "step": 1},
    {"kind": "slider", "key": "tint", "label": ("Blue tint", "Синий оттенок"), "min": 0, "max": 1, "default": 0.8, "fmt": ("%.1f", "%.1f"), "step": 0.1},
    {"kind": "choice", "key": "walk", "label": ("Faster walking in slow-mo", "Быстрее ходьба в замедлении"), "default": False, "choices": [(False, "Off", "Выкл"), (True, "On (approximation)", "Вкл (приближённо)")]},
    {"kind": "choice", "key": "hint", "label": ("Hint at level start", "Подсказка при старте"), "default": True, "choices": [(True, "Show", "Показывать"), (False, "Hide", "Скрыть")]},
]

if __name__ == "__main__":
    gen_options(os.path.join(HERE, "..", "mod", "options.lua"), ("Time Slow", "Замедление времени"),
                ("Hold a key to slow the world down", "Удерживайте клавишу, чтобы замедлить мир"), ROWS, accent=(0.5, 0.8, 1.0))
    print("wrote options.lua")
