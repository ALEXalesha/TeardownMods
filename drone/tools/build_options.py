"""Generate mod/options.lua for the Camera Drone."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from options_gen import gen_options  # noqa: E402

YN = [(True, "Yes", "Да"), (False, "No", "Нет")]
ROWS = [
    {"kind": "slider", "key": "speed", "label": ("Max speed", "Макс. скорость"), "min": 5, "max": 25, "default": 12.0, "fmt": ("%.0f m/s", "%.0f м/с"), "step": 1},
    {"kind": "slider", "key": "range", "label": ("Signal range", "Дальность связи"), "min": 50, "max": 500, "default": 150.0, "fmt": ("%.0f m", "%.0f м"), "step": 10},
    {"kind": "choice", "key": "battery", "label": ("Battery", "Батарея"), "default": True, "choices": [(True, "Limited", "Ограничена"), (False, "Unlimited", "Без ограничений")]},
    {"kind": "slider", "key": "minutes", "label": ("Battery lasts", "Батареи хватает на"), "min": 1, "max": 10, "default": 3.0, "fmt": ("%.0f min", "%.0f мин"), "step": 1},
    {"kind": "slider", "key": "bombs", "label": ("Bombs per flight", "Бомб за полёт"), "min": 1, "max": 10, "default": 3.0, "fmt": ("%.0f", "%.0f"), "step": 1},
    {"kind": "choice", "key": "grenade", "label": ("Drop Singularity Grenade", "Сбрасывать грав. гранату"), "default": True, "choices": [(True, "If that mod is on", "Если тот мод включён"), (False, "No, own bomb", "Нет, своя бомба")]},
    {"kind": "slider", "key": "bombsize", "label": ("Own bomb size", "Сила своей бомбы"), "min": 0.5, "max": 2.0, "default": 1.0, "fmt": ("%.1f", "%.1f"), "step": 0.1},
    {"kind": "slider", "key": "crash", "label": ("Breaks at impact of", "Ломается при ударе"), "min": 4, "max": 20, "default": 9.0, "fmt": ("%.0f m/s", "%.0f м/с"), "step": 1},
    {"kind": "slider", "key": "sens", "label": ("Mouse sensitivity", "Чувствительность мыши"), "min": 0.2, "max": 3, "default": 1.0, "fmt": ("x%.1f", "x%.1f"), "step": 0.1},
    {"kind": "slider", "key": "fov", "label": ("Camera FOV", "Угол обзора камеры"), "min": 60, "max": 110, "default": 90.0, "fmt": ("%.0f°", "%.0f°"), "step": 5},
    {"kind": "choice", "key": "debugline", "label": ("Debug line (for testing)", "Строка отладки (для проверки)"), "default": False, "choices": YN},
    {"kind": "choice", "key": "freeze", "label": ("Freeze player while flying", "Тело игрока стоит"), "default": True, "choices": YN},
]

if __name__ == "__main__":
    gen_options(os.path.join(HERE, "..", "mod", "options.lua"), ("Camera Drone", "Дрон с камерой"),
                ("Fly, look, drop", "Летай, смотри, сбрасывай"), ROWS, accent=(0.4, 0.9, 0.5))
    print("wrote options.lua")
