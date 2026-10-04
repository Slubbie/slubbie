#!/usr/bin/env python3
"""Render side and top views of dumped course geometry (from test_dump.luau)."""
import sys
from PIL import Image, ImageDraw

def load(path):
    courses = {}
    current = None
    for line in open(path):
        line = line.rstrip("\n")
        if line.startswith("COURSE|"):
            current = line.split("|")[1]
            courses[current] = {"parts": [], "cps": [], "tokens": []}
        elif line.startswith("PART|") and current:
            f = line.split("|")
            vals = list(map(float, f[2:17]))
            courses[current]["parts"].append({
                "name": f[1], "pos": vals[0:3], "rot": vals[3:12], "size": vals[12:15],
                "color": tuple(int(v) for v in f[17:20]), "transp": float(f[20]), "tags": f[21]})
        elif line.startswith("CP|") and current:
            courses[current]["cps"].append(list(map(float, line.split("|")[1:4])))
        elif line.startswith("TOKEN|") and current:
            courses[current]["tokens"].append(list(map(float, line.split("|")[1:4])))
    return courses

def corners(p):
    x, y, z = p["pos"]; r = p["rot"]; sx, sy, sz = [s / 2 for s in p["size"]]
    out = []
    for dx in (-sx, sx):
        for dy in (-sy, sy):
            for dz in (-sz, sz):
                out.append((x + r[0]*dx + r[1]*dy + r[2]*dz, y + r[3]*dx + r[4]*dy + r[5]*dz, z + r[6]*dx + r[7]*dy + r[8]*dz))
    return out

def hull(points):
    pts = sorted(set(points))
    if len(pts) <= 2:
        return pts
    def cross(o, a, b):
        return (a[0]-o[0])*(b[1]-o[1]) - (a[1]-o[1])*(b[0]-o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0: lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0: upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]

def render(name, course, out, scale=3):
    parts = [p for p in course["parts"] if p["transp"] < 1 or "Course" in p["tags"]]
    allc = [c for p in parts for c in corners(p)]
    # Course runs along -Z. Side view: u = -z (forward), v = y. Top view: u = -z, v = x.
    umin = min(-c[2] for c in allc) - 5; umax = max(-c[2] for c in allc) + 5
    ymin = min(c[1] for c in allc) - 5; ymax = max(c[1] for c in allc) + 5
    xmin = min(c[0] for c in allc) - 5; xmax = max(c[0] for c in allc) + 5
    W = int((umax - umin) * scale)
    H1 = int((ymax - ymin) * scale); H2 = int((xmax - xmin) * scale)
    img = Image.new("RGB", (W, H1 + H2 + 30), (25, 28, 36))
    d = ImageDraw.Draw(img, "RGBA")
    d.text((5, 5), name + " (side / top)", fill=(255, 255, 255))
    def side(c): return ((-c[2] - umin) * scale, H1 - (c[1] - ymin) * scale)
    def top(c): return ((-c[2] - umin) * scale, H1 + 30 + (c[0] - xmin) * scale)
    order = sorted(parts, key=lambda p: p["pos"][0])
    for p in order:
        cs = corners(p)
        alpha = 255 if p["transp"] < 0.5 else 110
        if p["transp"] >= 1: alpha = 40
        col = p["color"] + (alpha,)
        d.polygon(hull([side(c) for c in cs]), fill=col, outline=(0, 0, 0, 120))
    for p in sorted(parts, key=lambda p: p["pos"][1]):
        cs = corners(p)
        alpha = 255 if p["transp"] < 0.5 else 110
        if p["transp"] >= 1: alpha = 40
        col = p["color"] + (alpha,)
        d.polygon(hull([top(c) for c in cs]), fill=col, outline=(0, 0, 0, 120))
    for cp in course["cps"]:
        for f in (side, top):
            u, v = f(cp); d.ellipse((u-4, v-4, u+4, v+4), outline=(0, 255, 120), width=2)
    for t in course["tokens"]:
        for f in (side, top):
            u, v = f(t); d.ellipse((u-3, v-3, u+3, v+3), fill=(255, 210, 60))
    img.save(out)

if __name__ == "__main__":
    data = load(sys.argv[1])
    outdir = sys.argv[2]
    for name, course in data.items():
        render(name, course, f"{outdir}/{name}.png")
        print("rendered", name)
