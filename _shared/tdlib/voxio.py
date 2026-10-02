"""MagicaVoxel .vox reader and writer (format version 150/200).

Writer supports several named models (shapes) placed with a scene graph
(nTRN/nGRP/nSHP), a 256-color palette (RGBA) and per-index MATL chunks
(used by Teardown for emissive / metal / glass looks).

Reader parses everything back so generators can verify their output.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass, field


# ---------------------------------------------------------------- data types

@dataclass
class Model:
    name: str
    size: tuple[int, int, int]
    voxels: dict[tuple[int, int, int], int] = field(default_factory=dict)  # (x,y,z) -> palette index 1..255
    offset: tuple[int, int, int] = (0, 0, 0)  # translation of the model centre in voxels

    def set(self, x: int, y: int, z: int, idx: int) -> None:
        sx, sy, sz = self.size
        if 0 <= x < sx and 0 <= y < sy and 0 <= z < sz and 1 <= idx <= 255:
            self.voxels[(x, y, z)] = idx

    def clear(self, x: int, y: int, z: int) -> None:
        self.voxels.pop((x, y, z), None)


@dataclass
class VoxFile:
    models: list[Model] = field(default_factory=list)
    palette: list[tuple[int, int, int, int]] = field(default_factory=lambda: [(0, 0, 0, 255)] * 256)
    # palette index (1..255) -> dict of MATL properties, e.g. {"_type": "_emit", "_emit": "0.8"}
    materials: dict[int, dict[str, str]] = field(default_factory=dict)
    chunk_ids: list[str] = field(default_factory=list)  # filled by reader, for inspection
    names: list[str] = field(default_factory=list)  # filled by reader: shape names in scene graph order

    def set_color(self, idx: int, rgb: tuple[int, int, int], a: int = 255) -> None:
        # palette entry for voxel index idx is stored at slot idx-1
        self.palette[idx - 1] = (rgb[0], rgb[1], rgb[2], a)

    def color_of(self, idx: int) -> tuple[int, int, int, int]:
        return self.palette[idx - 1]


# ---------------------------------------------------------------- writing

def _chunk(cid: bytes, content: bytes, children: bytes = b"") -> bytes:
    assert len(cid) == 4
    return cid + struct.pack("<ii", len(content), len(children)) + content + children


def _vstr(s: str) -> bytes:
    b = s.encode("utf-8")
    return struct.pack("<i", len(b)) + b


def _vdict(d: dict[str, str]) -> bytes:
    out = struct.pack("<i", len(d))
    for k, v in d.items():
        out += _vstr(k) + _vstr(str(v))
    return out


def write_vox(path: str, vf: VoxFile) -> None:
    children = b""
    for m in vf.models:
        sx, sy, sz = m.size
        assert max(m.size) <= 256, "MagicaVoxel models are limited to 256^3"
        children += _chunk(b"SIZE", struct.pack("<iii", sx, sy, sz))
        xyzi = struct.pack("<i", len(m.voxels))
        for (x, y, z), i in sorted(m.voxels.items()):
            xyzi += struct.pack("<BBBB", x, y, z, i)
        children += _chunk(b"XYZI", xyzi)

    # Scene graph: root transform 0 -> group 1 -> (transform, shape) per model
    node_id = 0
    graph = b""
    n = len(vf.models)
    child_ids = [2 + 2 * k for k in range(n)]
    graph += _chunk(b"nTRN", struct.pack("<i", 0) + _vdict({}) + struct.pack("<iiii", 1, -1, -1, 1) + _vdict({}))
    graph += _chunk(b"nGRP", struct.pack("<i", 1) + _vdict({}) + struct.pack("<i", n) + b"".join(struct.pack("<i", c) for c in child_ids))
    for k, m in enumerate(vf.models):
        tid = 2 + 2 * k
        sid = tid + 1
        ox, oy, oz = m.offset
        graph += _chunk(b"nTRN", struct.pack("<i", tid) + _vdict({"_name": m.name}) + struct.pack("<iiii", sid, -1, -1, 1)
                        + _vdict({"_t": f"{ox} {oy} {oz}"}))
        graph += _chunk(b"nSHP", struct.pack("<i", sid) + _vdict({}) + struct.pack("<i", 1) + struct.pack("<i", k) + _vdict({}))
    del node_id
    children += graph

    rgba = b"".join(struct.pack("<BBBB", *c) for c in vf.palette)
    children += _chunk(b"RGBA", rgba)

    for idx, props in sorted(vf.materials.items()):
        children += _chunk(b"MATL", struct.pack("<i", idx) + _vdict(props))

    data = b"VOX " + struct.pack("<i", 150) + _chunk(b"MAIN", b"", children)
    with open(path, "wb") as f:
        f.write(data)


# ---------------------------------------------------------------- reading

def _rstr(b: bytes, o: int) -> tuple[str, int]:
    (n,) = struct.unpack_from("<i", b, o)
    o += 4
    return b[o:o + n].decode("utf-8", "replace"), o + n


def _rdict(b: bytes, o: int) -> tuple[dict[str, str], int]:
    (n,) = struct.unpack_from("<i", b, o)
    o += 4
    d = {}
    for _ in range(n):
        k, o = _rstr(b, o)
        v, o = _rstr(b, o)
        d[k] = v
    return d, o


def read_vox(path: str) -> VoxFile:
    with open(path, "rb") as f:
        b = f.read()
    if b[:4] != b"VOX ":
        raise ValueError("not a vox file")
    (version,) = struct.unpack_from("<i", b, 4)
    if version not in (150, 200):
        raise ValueError(f"unexpected vox version {version}")
    vf = VoxFile()
    o = 8
    cid = b[o:o + 4]
    if cid != b"MAIN":
        raise ValueError("MAIN chunk missing")
    _, child_len = struct.unpack_from("<ii", b, o + 4)
    o += 12
    end = o + child_len
    if end != len(b):
        raise ValueError(f"MAIN children size {child_len} does not match file ({len(b) - 20})")
    pending_size = None
    shape_names: dict[int, str] = {}  # model index -> name
    trn_name: dict[int, str] = {}  # child node -> name
    trn_t: dict[int, tuple[int, int, int]] = {}  # child node -> translation
    shp_model: dict[int, int] = {}  # shape node id -> model index
    while o < end:
        cid = b[o:o + 4].decode("ascii", "replace")
        clen, chlen = struct.unpack_from("<ii", b, o + 4)
        c = b[o + 12:o + 12 + clen]
        vf.chunk_ids.append(cid)
        if cid == "SIZE":
            pending_size = struct.unpack_from("<iii", c, 0)
        elif cid == "XYZI":
            (n,) = struct.unpack_from("<i", c, 0)
            if len(c) != 4 + 4 * n:
                raise ValueError("XYZI size mismatch")
            m = Model(name=f"model{len(vf.models)}", size=tuple(pending_size))
            for k in range(n):
                x, y, z, i = struct.unpack_from("<BBBB", c, 4 + 4 * k)
                if not (x < m.size[0] and y < m.size[1] and z < m.size[2]):
                    raise ValueError("voxel outside model bounds")
                if i == 0:
                    raise ValueError("voxel with palette index 0")
                m.voxels[(x, y, z)] = i
            vf.models.append(m)
        elif cid == "RGBA":
            vf.palette = [tuple(c[4 * k:4 * k + 4]) for k in range(256)]
        elif cid == "MATL":
            (idx,) = struct.unpack_from("<i", c, 0)
            props, _ = _rdict(c, 4)
            vf.materials[idx] = props
        elif cid == "nTRN":
            (nid,) = struct.unpack_from("<i", c, 0)
            attrs, p = _rdict(c, 4)
            child, _res, _layer, nframes = struct.unpack_from("<iiii", c, p)
            p += 16
            for _f in range(nframes):
                fr, p = _rdict(c, p)
                if "_t" in fr:
                    trn_t[child] = tuple(int(float(v)) for v in fr["_t"].split())
            if "_name" in attrs:
                trn_name[child] = attrs["_name"]
        elif cid == "nSHP":
            (nid,) = struct.unpack_from("<i", c, 0)
            _attrs, p = _rdict(c, 4)
            (nm,) = struct.unpack_from("<i", c, p)
            p += 4
            for _k in range(nm):
                (mid,) = struct.unpack_from("<i", c, p)
                p += 4
                _mattr, p = _rdict(c, p)
                shp_model[nid] = mid
        o += 12 + clen + chlen
    for nid, mid in shp_model.items():
        if nid in trn_name and mid < len(vf.models):
            vf.models[mid].name = trn_name[nid]
            shape_names[mid] = trn_name[nid]
        if nid in trn_t and mid < len(vf.models):
            vf.models[mid].offset = trn_t[nid]
    vf.names = [m.name for m in vf.models]
    return vf


def summary(path: str) -> str:
    vf = read_vox(path)
    lines = [f"{path}: {len(vf.models)} model(s); chunks: {sorted(set(vf.chunk_ids))}"]
    for m in vf.models:
        used = sorted(set(m.voxels.values()))
        lines.append(f"  {m.name}: size={m.size} voxels={len(m.voxels)} palette idx used={used[:20]}{'...' if len(used) > 20 else ''}")
    if vf.materials:
        mats = {k: v for k, v in vf.materials.items() if v.get('_type', '_diffuse') != '_diffuse'}
        lines.append(f"  non-diffuse materials: {mats}")
    return "\n".join(lines)


if __name__ == "__main__":
    import sys
    for p in sys.argv[1:]:
        print(summary(p))
