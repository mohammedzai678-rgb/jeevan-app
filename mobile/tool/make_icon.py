"""Generates the Jeevan launcher icon set (legacy PNGs + adaptive vector).

Logo: crimson squircle, white heart, crimson ECG pulse running through the heart.
Geometry is expressed in a 100x100 box so the Flutter painter and the Android
vector drawable stay identical.
"""
from pathlib import Path

from PIL import Image, ImageDraw

RES = Path(__file__).resolve().parent.parent / "android" / "app" / "src" / "main" / "res"

# Heart outline (cubic beziers) in 100x100 space.
HEART = [
    ("M", (50, 88)),
    ("C", (20, 66), (8, 48), (8, 32)),
    ("C", (8, 18), (19, 10), (30, 10)),
    ("C", (39, 10), (46, 15), (50, 22)),
    ("C", (54, 15), (61, 10), (70, 10)),
    ("C", (81, 10), (92, 18), (92, 32)),
    ("C", (92, 48), (80, 66), (50, 88)),
]
PULSE = [(20, 50), (36, 50), (43, 33), (53, 68), (60, 44), (64, 50), (80, 50)]


def bezier(p0, p1, p2, p3, n=48):
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        x = u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def heart_points():
    pts, cur = [], None
    for seg in HEART:
        if seg[0] == "M":
            cur = seg[1]
            pts.append(cur)
        else:
            pts.extend(bezier(cur, seg[1], seg[2], seg[3]))
            cur = seg[3]
    return pts


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def render(size, rounded=True, scale=0.62):
    ss = 4
    s = size * ss
    top, bottom = (255, 94, 108), (205, 31, 52)
    grad = Image.new("RGB", (s, s))
    d = ImageDraw.Draw(grad)
    for y in range(s):
        d.line([(0, y), (s, y)], fill=lerp(top, bottom, y / (s - 1)))
    mask = Image.new("L", (s, s), 0)
    md = ImageDraw.Draw(mask)
    if rounded:
        md.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.26), fill=255)
    else:
        md.rectangle([0, 0, s, s], fill=255)
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    img.paste(grad, (0, 0), mask)

    box = s * scale
    ox = (s - box) / 2
    oy = (s - box) / 2 + s * 0.012

    def tx(p):
        return (ox + p[0] / 100 * box, oy + p[1] / 100 * box)

    draw = ImageDraw.Draw(img)
    # soft shadow under heart
    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.polygon([(tx(p)[0], tx(p)[1] + s * 0.012) for p in heart_points()], fill=(120, 0, 20, 70))
    img = Image.alpha_composite(img, shadow)
    draw = ImageDraw.Draw(img)
    draw.polygon([tx(p) for p in heart_points()], fill=(255, 255, 255, 255))
    pulse = [tx(p) for p in PULSE]
    w = int(box * 0.062)
    draw.line(pulse, fill=(214, 40, 57, 255), width=w, joint="curve")
    for p in (pulse[0], pulse[-1]):
        draw.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=(214, 40, 57, 255))
    return img.resize((size, size), Image.LANCZOS)


def main():
    for name, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        render(px).save(RES / f"mipmap-{name}" / "ic_launcher.png")
    render(512).save(Path(__file__).parent / "jeevan_logo_512.png")


if __name__ == "__main__":
    main()
# Jeevan sync: 2026-11-13
