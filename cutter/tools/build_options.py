"""Generate mod/options.lua for the Cutter."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from options_gen import gen_options  # noqa: E402

YN = [(True, "Yes", "Да"), (False, "No", "Нет")]
ROWS = [
    {"kind": "slider", "key": "kerf", "label": ("Kerf width", "Ширина реза"), "min": 0.1, "max": 0.4, "default": 0.2, "fmt": ("%.2f m", "%.2f м"), "step": 0.02},
    {"kind": "slider", "key": "depth", "label": ("Max depth", "Макс. глубина"), "min": 0.2, "max": 3, "default": 1.0, "fmt": ("%.1f m", "%.1f м"), "step": 0.1},
    {"kind": "slider", "key": "maxlen", "label": ("Max cut length", "Макс. длина реза"), "min": 0.5, "max": 10, "default": 4.0, "fmt": ("%.1f m", "%.1f м"), "step": 0.5},
    {"kind": "slider", "key": "reach", "label": ("Reach", "Дотягивается на"), "min": 2, "max": 15, "default": 6.0, "fmt": ("%.0f m", "%.0f м"), "step": 1},
    {"kind": "slider", "key": "budget", "label": ("Holes per step (speed)", "Дыр за шаг (скорость)"), "min": 4, "max": 40, "default": 12.0, "fmt": ("%.0f", "%.0f"), "step": 1},
    {"kind": "choice", "key": "metal", "label": ("Cuts metal", "Режет металл"), "default": True, "choices": YN},
    {"kind": "choice", "key": "masonry", "label": ("Cuts concrete and brick", "Режет бетон и кирпич"), "default": True, "choices": YN},
    {"kind": "slider", "key": "masonrycost", "label": ("Concrete is slower by", "Бетон медленнее в"), "min": 1, "max": 6, "default": 3.0, "fmt": ("x%.1f", "x%.1f"), "step": 0.5},
    {"kind": "choice", "key": "hard", "label": ("Cuts hard metal", "Режет прочный металл"), "default": False, "choices": [(False, "No", "Нет"), (True, "Yes", "Да")]},
    {"kind": "choice", "key": "sparks", "label": ("Sparks and dust", "Искры и пыль"), "default": True, "choices": YN},
]

if __name__ == "__main__":
    gen_options(os.path.join(HERE, "..", "mod", "options.lua"), ("Cutter", "Резак"),
                ("Hold LMB, sweep, release", "Зажмите ЛКМ, проведите, отпустите"), ROWS, accent=(1.0, 0.55, 0.15))
    print("wrote options.lua")
