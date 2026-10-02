"""Helpers for generated preview images, icons and UI textures."""
from __future__ import annotations

import io
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from voxio import Model, VoxFile
from render import render_models

TEARDOWN = os.environ.get("TEARDOWN_DIR", r"C:\Program Files (x86)\Steam\steamapps\common\Teardown")
FONT_DIR = os.path.join(TEARDOWN, "data", "ui", "font")


def font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont:
    name = "bold.ttf" if bold else "regular.ttf"
    for p in (os.path.join(FONT_DIR, name), "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf"):
        if os.path.isfile(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def vertical_gradient(size, top, bottom) -> Image.Image:
    w, h = size
    t = np.linspace(0, 1, h)[:, None, None]
    a = np.array(top, np.float32)[None, None, :]
    b = np.array(bottom, np.float32)[None, None, :]
    arr = np.repeat(a * (1 - t) + b * t, w, axis=1)
    return Image.fromarray(arr.astype(np.uint8), "RGBA" if len(top) == 4 else "RGB").convert("RGBA")


def glow_spot(size, center, radius, color, power=2.0) -> Image.Image:
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2) / radius
    a = np.clip(1 - d, 0, 1) ** power
    arr = np.zeros((h, w, 4), np.float32)
    arr[..., 0], arr[..., 1], arr[..., 2] = color[0], color[1], color[2]
    arr[..., 3] = a * 255
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def add(base: Image.Image, top: Image.Image, gain: float = 1.0) -> Image.Image:
    a = np.asarray(base.convert("RGBA")).astype(np.float32)
    b = np.asarray(top.convert("RGBA")).astype(np.float32)
    a[..., :3] = np.clip(a[..., :3] + b[..., :3] * (b[..., 3:4] / 255.0) * gain, 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def text_with_glow(img: Image.Image, xy, text, fnt, fill=(255, 255, 255), glow=(160, 80, 255), glow_r=8, anchor="mm",
                   stroke=2) -> Image.Image:
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.text(xy, text, font=fnt, fill=glow + (255,), anchor=anchor, stroke_width=stroke + 2, stroke_fill=glow + (255,))
    layer = layer.filter(ImageFilter.GaussianBlur(glow_r))
    img = add(img, layer, 1.2)
    d2 = ImageDraw.Draw(img)
    d2.text(xy, text, font=fnt, fill=fill + (255,), anchor=anchor, stroke_width=stroke, stroke_fill=(20, 10, 30, 255))
    return img


def debris_model(kind: str, rnd: random.Random) -> tuple[VoxFile, Model]:
    """Small random voxel props for preview scenes: plank, crate, brick, glass shard, barrel."""
    vf = VoxFile()
    cols = {
        "plank": [(150, 104, 62), (126, 86, 50), (170, 122, 76)],
        "crate": [(168, 120, 70), (120, 84, 46), (190, 140, 84)],
        "brick": [(150, 70, 52), (128, 58, 44), (170, 86, 64)],
        "glass": [(150, 200, 220), (120, 170, 200), (190, 230, 240)],
        "barrel": [(170, 40, 34), (60, 60, 64), (200, 60, 50)],
        "concrete": [(150, 150, 146), (128, 128, 124), (170, 170, 166)],
        "metal": [(110, 116, 126), (84, 90, 100), (140, 146, 156)],
    }[kind]
    for i, c in enumerate(cols):
        vf.set_color(10 + i, c)
    if kind == "plank":
        m = Model("p", (rnd.randint(8, 14), 3, 1))
    elif kind == "crate":
        s = rnd.randint(4, 6)
        m = Model("p", (s, s, s))
    elif kind == "brick":
        m = Model("p", (4, 2, 2))
    elif kind == "glass":
        m = Model("p", (rnd.randint(3, 6), rnd.randint(3, 6), 1))
    elif kind == "barrel":
        m = Model("p", (5, 5, 7))
    else:
        m = Model("p", (rnd.randint(3, 6), rnd.randint(2, 5), rnd.randint(2, 4)))
    sx, sy, sz = m.size
    for x in range(sx):
        for y in range(sy):
            for z in range(sz):
                if kind == "barrel":
                    if (x - 2) ** 2 + (y - 2) ** 2 > 5:
                        continue
                    idx = 11 if z in (0, sz - 1) else (12 if z in (2, 4) else 10)
                elif kind == "crate":
                    edge = sum(v in (0, s - 1) for v, s in ((x, sx), (y, sy), (z, sz))) >= 2
                    idx = 11 if edge else 10 + rnd.randint(0, 2) % 2 * 2
                elif kind == "glass" and rnd.random() < 0.2:
                    continue
                else:
                    idx = 10 + rnd.choice((0, 0, 1, 2))
                m.set(x, y, z, idx)
    vf.models = [m]
    return vf, m


def render_debris(kind: str, rnd: random.Random, px: float) -> Image.Image:
    vf, m = debris_model(kind, rnd)
    return render_models(vf, [m], yaw=rnd.uniform(0, 360), pitch=rnd.uniform(10, 70), px=px, ss=2, glow=0, outline=True)


def motion_blur(img: Image.Image, dx: float, dy: float, steps: int = 6) -> Image.Image:
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    w, h = img.size
    big = Image.new("RGBA", (w + int(abs(dx)) * 2 + 4, h + int(abs(dy)) * 2 + 4), (0, 0, 0, 0))
    acc = np.zeros((big.size[1], big.size[0], 4), np.float32)
    for i in range(steps):
        t = i / max(1, steps - 1)
        tmp = Image.new("RGBA", big.size, (0, 0, 0, 0))
        tmp.paste(img, (int(abs(dx) + 2 + dx * t), int(abs(dy) + 2 + dy * t)))
        acc += np.asarray(tmp).astype(np.float32) * (0.25 + 0.75 * t)
    acc /= sum(0.25 + 0.75 * (i / max(1, steps - 1)) for i in range(steps))
    return Image.fromarray(np.clip(acc, 0, 255).astype(np.uint8), "RGBA")


def save_jpg(img: Image.Image, path: str, max_bytes: int = 1_000_000) -> int:
    rgb = img.convert("RGB")
    for q in (92, 88, 84, 80, 75, 70, 60):
        buf = io.BytesIO()
        rgb.save(buf, "JPEG", quality=q, optimize=True)
        if buf.tell() <= max_bytes:
            with open(path, "wb") as f:
                f.write(buf.getvalue())
            return buf.tell()
    raise RuntimeError("could not fit preview under the size limit")


def dot_png(path: str, size: int = 24, color=(255, 255, 255)) -> None:
    ss = 4
    im = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((ss, ss, size * ss - ss, size * ss - ss), fill=color + (255,), outline=(40, 30, 60, 255), width=ss * 2)
    im.resize((size, size), Image.LANCZOS).save(path)


def vignette_png(path: str, w: int = 512, h: int = 288) -> None:
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = (xx / (w - 1) - 0.5) * 2
    ny = (yy / (h - 1) - 0.5) * 2
    d = np.sqrt(nx ** 2 * 0.9 + ny ** 2)
    a = np.clip((d - 0.45) / 0.9, 0, 1) ** 1.6
    arr = np.zeros((h, w, 4), np.uint8)
    arr[..., :3] = 255
    arr[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(arr, "RGBA").save(path)


def car_model(body=(200, 40, 36), seed: int = 1) -> tuple[VoxFile, Model]:
    """Boxy voxel car (for previews): body, cabin with windows, four wheels, lights."""
    vf = VoxFile()
    vf.set_color(10, body)
    vf.set_color(11, tuple(int(c * 0.7) for c in body))
    vf.set_color(12, (150, 200, 230))   # glass
    vf.set_color(13, (25, 25, 28))      # tyre
    vf.set_color(14, (170, 170, 176))   # rim
    vf.set_color(15, (255, 240, 180))   # headlight
    vf.set_color(16, (220, 30, 30))     # tail light
    vf.materials[15] = {"_type": "_emit", "_emit": "1", "_flux": "3"}
    vf.materials[16] = {"_type": "_emit", "_emit": "0.8", "_flux": "3"}
    m = Model("car", (12, 22, 9))
    for x in range(12):
        for y in range(22):
            for z in range(2, 5):
                if 1 <= x <= 10:
                    m.set(x, y, z, 10 if z > 2 else 11)
    for x in range(2, 10):
        for y in range(6, 16):
            for z in range(5, 8):
                win = (z in (5, 6)) and (x in (2, 9) or y in (6, 15))
                m.set(x, y, z, 12 if win else 10)
    for x in (2, 3, 8, 9):
        m.set(x, 0, 4, 15) if x in (2, 9) else None
        m.set(x, 21, 4, 16) if x in (2, 9) else None
    for (wx, wy) in ((0, 4), (11, 4), (0, 17), (11, 17)):
        for dy in range(-2, 2):
            for dz in range(0, 4):
                if (dy + 0.5) ** 2 + (dz - 1.5) ** 2 <= 4.6:
                    idx = 14 if abs(dy + 0.5) < 1 and abs(dz - 1.5) < 1 else 13
                    m.set(wx, wy + dy, dz, idx)
    vf.models = [m]
    return vf, m
