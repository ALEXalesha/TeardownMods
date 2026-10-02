"""Generate mod/options.lua for Gravity Change."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from options_gen import gen_options  # noqa: E402

ROWS = [
    {"kind": "choice", "key": "key", "label": ("Key", "Клавиша"), "default": "g", "choices": [("g", "G", "G"), ("j", "J", "J"), ("k", "K", "K")]},
    {"kind": "slider", "key": "trans", "label": ("Transition", "Плавность смены"), "min": 0, "max": 5, "default": 1.5, "fmt": ("%.1f s", "%.1f с"), "step": 0.1},
    {"kind": "slider", "key": "reverse", "label": ("Reverse strength", "Сила обратной"), "min": 1, "max": 10, "default": 4.0, "fmt": ("%.1f m/s²", "%.1f м/с²"), "step": 0.5},
    {"kind": "slider", "key": "sideways", "label": ("Sideways strength", "Сила боковой"), "min": 2, "max": 10, "default": 6.0, "fmt": ("%.1f m/s²", "%.1f м/с²"), "step": 0.5},
    {"kind": "choice", "key": "autoreturn", "label": ("Back to Earth after", "Вернуть Землю через"), "default": 0.0,
     "choices": [(0.0, "Never", "Никогда"), (10.0, "10 s", "10 с"), (30.0, "30 s", "30 с"), (60.0, "60 s", "60 с")]},
    {"kind": "slider", "key": "wakeradius", "label": ("Wake objects within", "Будить предметы в радиусе"), "min": 20, "max": 120, "default": 60.0, "fmt": ("%.0f m", "%.0f м"), "step": 5},
    {"kind": "choice", "key": "thrusters", "label": ("Zero-G thrusters", "Двигатели в невесомости"), "default": True, "choices": [(True, "On", "Вкл"), (False, "Off", "Выкл")]},
    {"kind": "choice", "key": "indicator", "label": ("Indicator", "Индикатор"), "default": True, "choices": [(True, "Show", "Показывать"), (False, "Hide", "Скрыть")]},
]

if __name__ == "__main__":
    gen_options(os.path.join(HERE, "..", "mod", "options.lua"), ("Gravity Change", "Смена гравитации"),
                ("Earth, Moon, Mars, zero-G, reverse, sideways", "Земля, Луна, Марс, невесомость, обратная, вбок"), ROWS, accent=(0.4, 0.8, 1.0))
    print("wrote options.lua")
