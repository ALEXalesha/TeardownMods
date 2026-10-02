"""Write hand-held tool prefabs in the format used by the game's own tools."""
from __future__ import annotations

DEFAULT_POSES = {
    "fp_action": ("0.3 -0.35 -0.45", "0.0 0.0 0.0"),
    "tp_action": ("0.35 -0.1 -0.45", "0 0 0"),
    "tp_action_crouch": ("0.35 -0.2 -0.35", "0 0 0"),
    "tp_run": ("0.35 -0.35 -0.3", "10 10 -10"),
    "tp_jump": ("0.4 -0.275 -0.325", "20.0 5 10"),
    "tp_crouch": ("0.375 -0.55 -0.1", "-20 -10 20"),
    "tp_swim": ("0.35 -0.35 -0.35", "10.0 5 10"),
}


def tool_prefab(path: str, vox: str, scale: float, rh=("0.0 0.0 0.0", "0.0 90.0 0.0"), lh=None,
                poses: dict | None = None, locations: dict | None = None, texture: str | None = None) -> None:
    p = dict(DEFAULT_POSES)
    if poses:
        p.update(poses)
    name = path.replace("\\", "/").split("/mod/")[-1]
    lines = ['<prefab version="1.5.4">', f'\t<group name="instance=MOD/{name}" pos="0.0 0.0 0.0" rot="0.0 0.0 0.0">',
             '\t\t<group name="eye_space">']
    for k, (pos, rot) in p.items():
        lines.append(f'\t\t\t<location name="{k}" tags="name={k}" pos="{pos}" rot="{rot}"/>')
    lines.append('\t\t</group>')
    lines.append('\t\t<group name="tool_space">')
    lines.append('\t\t\t<body dynamic="false">')
    tex = f' texture="{texture}"' if texture else ""
    lines.append(f'\t\t\t\t<vox{tex} file="{vox}" scale="{scale}"/>')
    lines.append('\t\t\t</body>')
    for pose in ("tp_action", "tp_run", "tp_crouch"):
        lines.append(f'\t\t\t<location name="{pose}_rh" tags="name={pose}_rh ik_hand" pos="{rh[0]}" rot="{rh[1]}"/>')
        if lh:
            lines.append(f'\t\t\t<location name="{pose}_lh" tags="name={pose}_lh ik_hand" pos="{lh[0]}" rot="{lh[1]}"/>')
    for k, (pos, rot) in (locations or {}).items():
        lines.append(f'\t\t\t<location name="{k}" tags="name={k}" pos="{pos}" rot="{rot}"/>')
    lines.append('\t\t</group>')
    lines.append('\t</group>')
    lines.append('</prefab>')
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
