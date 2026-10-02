"""Generate mod/options.lua for Trampoline Floor."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from options_gen import gen_options  # noqa: E402

YN = [(True, "Yes", "Да"), (False, "No", "Нет")]
ROWS = [
    {"kind": "slider", "key": "restitution", "label": ("Bounciness (restitution)", "Упругость"), "min": 0.3, "max": 1.5, "default": 1.05, "fmt": ("%.2f", "%.2f"), "step": 0.05},
    {"kind": "slider", "key": "maxspeed", "label": ("Max bounce speed", "Макс. скорость отскока"), "min": 5, "max": 60, "default": 30.0, "fmt": ("%.0f m/s", "%.0f м/с"), "step": 1},
    {"kind": "slider", "key": "jumpboost", "label": ("Jump boost on contact", "Прибавка от прыжка"), "min": 0, "max": 15, "default": 6.0, "fmt": ("+%.0f m/s", "+%.0f м/с"), "step": 1},
    {"kind": "choice", "key": "players", "label": ("Players bounce", "Игроки прыгают"), "default": True, "choices": YN},
    {"kind": "choice", "key": "bodies", "label": ("Objects bounce", "Предметы прыгают"), "default": True, "choices": YN},
    {"kind": "choice", "key": "vehicles", "label": ("Vehicles bounce", "Машины прыгают"), "default": True, "choices": YN},
    {"kind": "slider", "key": "radius", "label": ("Global mode radius", "Радиус режима «вся земля»"), "min": 10, "max": 80, "default": 30.0, "fmt": ("%.0f m", "%.0f м"), "step": 5},
    {"kind": "choice", "key": "global", "label": ("Whole ground bounces at start", "Вся земля прыгает со старта"), "default": False, "choices": [(False, "No", "Нет"), (True, "Yes", "Да")]},
]

if __name__ == "__main__":
    gen_options(os.path.join(HERE, "..", "mod", "options.lua"), ("Trampoline Floor", "Пол-батут"),
                ("Boing!", "Бойнг!"), ROWS, accent=(0.3, 0.6, 1.0))
    print("wrote options.lua")
