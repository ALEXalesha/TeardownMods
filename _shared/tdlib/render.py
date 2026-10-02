"""Isometric voxel renderer (PIL) for previews and tool icons.

render_vox(vf, model_names=None, yaw=0, px=12) -> RGBA image with emissive glow.
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from voxio import VoxFile, Model


def _rot_yaw(x: float, z: float, yaw_deg: float) -> tuple[float, float]:
    a = math.radians(yaw_deg)
    c, s = math.cos(a), math.sin(a)
    return x * c - z * s, x * s + z * c


def render_models(vf: VoxFile, models: list[Model], yaw: float = 30.0, pitch: float = 30.0, px: float = 12.0,
                  ss: int = 3, glow: float = 1.0, outline: bool = True) -> Image.Image:
    """Render several models (using their offsets) into one RGBA image."""
    vox = {}
    for m in models:
        sx, sy, sz = m.size
        ox, oy, oz = m.offset
        for (x, y, z), i in m.voxels.items():
            # MagicaVoxel: z is up. Convert to y-up world: (x, z, y)
            wx = x - sx // 2 + ox
            wy = z - sz // 2 + oz
            wz = y - sy // 2 + oy
            vox[(round(wx * 2) / 2, round(wy * 2) / 2, round(wz * 2) / 2)] = i
    keys = set(vox.keys())
    s = px * ss
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))

    def proj(x, y, z):
        rx, rz = _rot_yaw(x, z, yaw)
        # orthographic: screen x = rx, screen y = -y*cp + rz*sp ; depth = rz*cp + y*sp
        return rx * s, (-y * cp + rz * sp) * s, rz * cp + y * sp

    # faces: (normal, 4 corner offsets)
    faces = [
        ((0, 1, 0), [(0, 1, 0), (1, 1, 0), (1, 1, 1), (0, 1, 1)], 1.0),
        ((0, -1, 0), [(0, 0, 0), (0, 0, 1), (1, 0, 1), (1, 0, 0)], 0.45),
        ((1, 0, 0), [(1, 0, 0), (1, 0, 1), (1, 1, 1), (1, 1, 0)], 0.80),
        ((-1, 0, 0), [(0, 0, 0), (0, 1, 0), (0, 1, 1), (0, 0, 1)], 0.70),
        ((0, 0, 1), [(0, 0, 1), (0, 1, 1), (1, 1, 1), (1, 0, 1)], 0.62),
        ((0, 0, -1), [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)], 0.75),
    ]
    polys = []
    for (x, y, z), idx in vox.items():
        for nrm, corners, shade in faces:
            nb = (x + nrm[0], y + nrm[1], z + nrm[2])
            if nb in keys:
                continue
            pts = [proj(x + c[0] - 0.5, y + c[1] - 0.5, z + c[2] - 0.5) for c in corners]
            # back-face cull: normal (rotated by yaw) against the direction to the camera
            rnx, rnz = _rot_yaw(nrm[0], nrm[2], yaw)
            if nrm[1] * sp + rnz * cp <= 1e-6:
                continue
            depth = sum(p[2] for p in pts) / 4
            polys.append((depth, [(p[0], p[1]) for p in pts], idx, shade, nrm))
    if not polys:
        return Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    polys.sort(key=lambda p: p[0])
    xs = [p[0] for poly in polys for p in poly[1]]
    ys = [p[1] for poly in polys for p in poly[1]]
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    pad = int(6 * ss + 40 * ss * glow)
    w, h = int(maxx - minx) + 2 * pad, int(maxy - miny) + 2 * pad
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    glow_img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    g = ImageDraw.Draw(glow_img)
    for depth, pts, idx, shade, nrm in polys:
        r, gg, b, al = vf.color_of(idx)
        mat = vf.materials.get(idx, {})
        emissive = mat.get("_type") == "_emit"
        if emissive:
            sh = 1.0
        else:
            sh = shade
        col = (int(min(255, r * sh)), int(min(255, gg * sh)), int(min(255, b * sh)), 255)
        pp = [(x - minx + pad, y - miny + pad) for x, y in pts]
        d.polygon(pp, fill=col, outline=(int(col[0] * 0.75), int(col[1] * 0.75), int(col[2] * 0.75), 255) if outline else None)
        if emissive and glow > 0:
            g.polygon(pp, fill=(r, gg, b, 255))
    if glow > 0:
        bl = glow_img.filter(ImageFilter.GaussianBlur(10 * ss * glow))
        bl2 = glow_img.filter(ImageFilter.GaussianBlur(3 * ss * glow))
        base = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        base = Image.alpha_composite(base, bl)
        base = Image.alpha_composite(base, img)
        arr = np.asarray(base).astype(np.float32)
        add = np.asarray(bl2).astype(np.float32)
        arr[..., :3] = np.clip(arr[..., :3] + add[..., :3] * (add[..., 3:4] / 255.0) * 0.6, 0, 255)
        img = Image.fromarray(arr.astype(np.uint8), "RGBA")
    img = img.resize((max(1, w // ss), max(1, h // ss)), Image.LANCZOS)
    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def render_vox(vf: VoxFile, names: list[str] | None = None, **kw) -> Image.Image:
    models = [m for m in vf.models if names is None or m.name in names]
    return render_models(vf, models, **kw)


def radial_gradient(size: tuple[int, int], center: tuple[float, float], radius: float,
                    inner: tuple[int, int, int, int], outer: tuple[int, int, int, int], power: float = 1.0) -> Image.Image:
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    dist = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2) / max(radius, 1e-3)
    t = np.clip(dist, 0, 1) ** power
    a = np.array(inner, np.float32)
    b = np.array(outer, np.float32)
    out = a[None, None, :] * (1 - t[..., None]) + b[None, None, :] * t[..., None]
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def add_images(base: Image.Image, top: Image.Image, gain: float = 1.0) -> Image.Image:
    """Additive blend (top premultiplied by its alpha)."""
    a = np.asarray(base.convert("RGBA")).astype(np.float32)
    b = np.asarray(top.convert("RGBA")).astype(np.float32)
    a[..., :3] = np.clip(a[..., :3] + b[..., :3] * (b[..., 3:4] / 255.0) * gain, 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")
