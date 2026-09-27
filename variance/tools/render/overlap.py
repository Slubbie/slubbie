#!/usr/bin/env python3
"""Checks snapshot frames for a body sinking into furniture.

For every frame, each limb of the chosen rig (Torso, arms, legs, head) is
tested against the chair and table parts with an oriented-box separating
axis test; the reported depth is how far the boxes interpenetrate along the
axis that separates them best. Anything under `--tolerance` studs is contact,
not clipping.

  python3 tools/render/overlap.py out/seat [--rig Character] [--tolerance 0.08]
"""

import glob
import json
import math
import os
import sys

LIMBS = {"Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg"}
FURNITURE_MODELS = ("Chair_", "Table")


def box(p):
    cf = p["CF"]
    c = (cf[0], cf[1], cf[2])
    r = cf[3:12]
    axes = [(r[0], r[3], r[6]), (r[1], r[4], r[7]), (r[2], r[5], r[8])]
    h = [s / 2 for s in p["S"]]
    return c, axes, h


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def penetration(a, b):
    ca, aa, ha = a
    cb, ab, hb = b
    d = (cb[0] - ca[0], cb[1] - ca[1], cb[2] - ca[2])
    best = math.inf
    candidates = aa + ab + [cross(x, y) for x in aa for y in ab]
    for axis in candidates:
        n = math.sqrt(dot(axis, axis))
        if n < 1e-6:
            continue
        axis = (axis[0] / n, axis[1] / n, axis[2] / n)
        ra = sum(ha[i] * abs(dot(aa[i], axis)) for i in range(3))
        rb = sum(hb[i] * abs(dot(ab[i], axis)) for i in range(3))
        overlap = ra + rb - abs(dot(d, axis))
        if overlap <= 0:
            return 0.0
        best = min(best, overlap)
    return best


def main():
    args = sys.argv[1:]
    rig = "Character"
    tolerance = 0.08
    seat_hint = None
    paths = []
    i = 0
    while i < len(args):
        if args[i] == "--rig":
            rig = args[i + 1]
            i += 2
        elif args[i] == "--tolerance":
            tolerance = float(args[i + 1])
            i += 2
        else:
            paths.append(args[i])
            i += 1
    files = []
    for p in paths:
        files += sorted(glob.glob(os.path.join(p, "*.json"))) if os.path.isdir(p) else [p]
    worst_overall = 0.0
    for f in files:
        frame = json.load(open(f))
        parts = frame["Scene"]["Parts"]
        limbs = [p for p in parts if p.get("Mdl") == rig and p["N"] in LIMBS]
        if not limbs:
            continue
        torso = next((p for p in limbs if p["N"] == "Torso"), limbs[0])
        tc = torso["CF"][:3]
        furniture = [
            p
            for p in parts
            if p.get("Mdl", "").startswith(FURNITURE_MODELS)
            and p["N"] not in ("Pipe", "Flange")
            and math.dist(p["CF"][:3], tc) < 9
        ]
        hits = []
        for limb in limbs:
            lb = box(limb)
            for part in furniture:
                depth = penetration(lb, box(part))
                if depth > tolerance:
                    hits.append((depth, limb["N"], part["Mdl"] + "." + part["N"]))
        hits.sort(reverse=True)
        worst = hits[0][0] if hits else 0.0
        worst_overall = max(worst_overall, worst)
        label = frame.get("Label", os.path.basename(f))
        if hits:
            print(f"{label}: " + ", ".join(f"{l} in {p} {d:.2f}" for d, l, p in hits[:4]))
        else:
            print(f"{label}: clear")
    print(f"worst penetration: {worst_overall:.2f} studs")
    sys.exit(1 if worst_overall > tolerance else 0)


if __name__ == "__main__":
    main()
