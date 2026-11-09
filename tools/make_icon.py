"""MNLOVO SAVER app icon — an eye whose pupil is a keyhole: it watches over what you keep.
Rendered at 4x and downsampled for clean edges.  Run: python3 tools/make_icon.py
"""
import json, math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XC = os.path.join(ROOT, "App", "Resources", "Assets.xcassets")
S = 4096
TEAL = np.array([57, 230, 200], float)
INDIGO = np.array([123, 108, 255], float)
VIOLET = np.array([196, 92, 255], float)


def grid():
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    return x, y


def to_img(arr):
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def background():
    x, y = grid()
    cx, cy = S * 0.5, S * 0.42
    d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / (S * 0.75)
    base = np.array([20, 22, 48], float) * (1 - d[..., None]) + np.array([4, 5, 10], float) * d[..., None]
    base = np.clip(base, 0, 255)

    def glow(gx, gy, r, col, k):
        dd = np.sqrt((x - gx) ** 2 + (y - gy) ** 2) / r
        a = np.clip(1 - dd, 0, 1) ** 2.2 * k
        return a[..., None] * col

    base += glow(S * 0.18, S * 0.12, S * 0.75, TEAL, 0.32)
    base += glow(S * 0.9, S * 0.95, S * 0.85, VIOLET, 0.30)
    base += glow(S * 0.5, S * 0.5, S * 0.45, INDIGO, 0.18)
    # fine grain so gradients never band
    base += np.random.default_rng(1).normal(0, 1.2, base.shape)
    return to_img(base).convert("RGBA")


def almond(cx, cy, w, h, steps=400):
    top, bot = [], []
    for t in np.linspace(0, 1, steps):
        # cubic-ish almond: pointed corners, full middle
        px = cx - w / 2 + w * t
        bulge = math.sin(math.pi * t) ** 0.85
        top.append((px, cy - h * bulge))
        bot.append((px, cy + h * bulge))
    return top + bot[::-1]


def gradient_fill(mask, c1, c2, angle_deg=35):
    x, y = grid()
    a = math.radians(angle_deg)
    t = ((x * math.cos(a) + y * math.sin(a)) / (S * 1.2))
    t = (t - t.min()) / (t.max() - t.min())
    col = c1 * (1 - t[..., None]) + c2 * t[..., None]
    rgba = np.dstack([col, np.array(mask, float)])
    return to_img(rgba)


def main():
    img = background()
    cx, cy = S / 2, S / 2
    W, H = S * 0.74, S * 0.205
    eye = almond(cx, cy, W, H)

    # outer glow
    glow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow).line(eye + [eye[0]], fill=255, width=int(S * 0.05), joint="curve")
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.03))
    img = Image.alpha_composite(img, gradient_fill(glow.point(lambda v: v * 0.75), TEAL, VIOLET))

    # eye interior: deep glass
    inner = Image.new("L", (S, S), 0)
    ImageDraw.Draw(inner).polygon(eye, fill=255)
    x, y = grid()
    dy = np.abs(y - cy) / H
    glass = np.zeros((S, S, 4))
    glass[..., :3] = np.array([10, 12, 26]) * (1 - dy[..., None] * 0.3) + np.array([24, 26, 58]) * (1 - dy[..., None]) * 0.35
    glass[..., 3] = np.array(inner, float)
    img = Image.alpha_composite(img, to_img(glass))

    # iris: angular gradient ring with fine radial fibres
    R = S * 0.165
    ang = np.arctan2(y - cy, x - cx)
    dist = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
    mix = (np.sin(ang * 2 + 0.6) + 1) / 2
    col = TEAL * mix[..., None] + INDIGO * (1 - mix[..., None])
    fibres = 0.82 + 0.18 * np.sin(ang * 90 + np.sin(ang * 7) * 2) * np.clip((dist - R * 0.45) / (R * 0.5), 0, 1)
    shade = np.clip(1.15 - (dist / R) ** 3 * 0.55, 0, 1.2)
    col = col * fibres[..., None] * shade[..., None]
    rim = np.clip(1 - np.abs(dist - R * 0.985) / (R * 0.035), 0, 1)
    col = col * (1 - rim[..., None] * 0.7)
    iris_a = np.clip((R - dist) / 6, 0, 1) * 255
    iris = to_img(np.dstack([col, iris_a]))
    iris_mask = Image.composite(iris, Image.new("RGBA", (S, S)), inner)
    img = Image.alpha_composite(img, iris_mask)

    # keyhole pupil
    kh = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(kh)
    r = R * 0.33
    kcy = cy - R * 0.12
    d.ellipse((cx - r, kcy - r, cx + r, kcy + r), fill=255)
    d.polygon([(cx - r * 0.42, kcy + r * 0.4), (cx + r * 0.42, kcy + r * 0.4),
               (cx + r * 0.72, cy + R * 0.55), (cx - r * 0.72, cy + R * 0.55)], fill=255)
    kh = kh.filter(ImageFilter.GaussianBlur(3))
    pupil = Image.new("RGBA", (S, S), (4, 5, 10, 255))
    pupil.putalpha(kh)
    # subtle teal light leaking from the keyhole edge
    edge = kh.filter(ImageFilter.GaussianBlur(S * 0.006))
    leak = Image.new("RGBA", (S, S), (57, 230, 200, 0))
    leak.putalpha(edge.point(lambda v: int(v * 0.55)))
    img = Image.alpha_composite(img, leak)
    img = Image.alpha_composite(img, pupil)

    # catchlights
    hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    hx, hy, hr = cx - R * 0.48, cy - R * 0.5, R * 0.17
    hd.ellipse((hx - hr, hy - hr, hx + hr, hy + hr), fill=(255, 255, 255, 235))
    hx2, hy2, hr2 = cx + R * 0.52, cy + R * 0.42, R * 0.065
    hd.ellipse((hx2 - hr2, hy2 - hr2, hx2 + hr2, hy2 + hr2), fill=(255, 255, 255, 150))
    hl = hl.filter(ImageFilter.GaussianBlur(4))
    img = Image.alpha_composite(img, Image.composite(hl, Image.new("RGBA", (S, S)), inner))

    # crisp gradient outline
    line = Image.new("L", (S, S), 0)
    ImageDraw.Draw(line).line(eye + [eye[0]], fill=255, width=int(S * 0.016), joint="curve")
    line = line.filter(ImageFilter.GaussianBlur(2))
    img = Image.alpha_composite(img, gradient_fill(line, TEAL, VIOLET))

    final = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)
    path = os.path.join(XC, "AppIcon.appiconset")
    os.makedirs(path, exist_ok=True)
    final.save(os.path.join(path, "icon-1024.png"))
    with open(os.path.join(path, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
    final.resize((512, 512), Image.LANCZOS).save(os.path.join(ROOT, "tools", "icon-preview.png"))
    # brand mark (transparent) for in-app use
    mark = img.crop((int(cx - W / 2 - S * 0.04), int(cy - H * 1.4), int(cx + W / 2 + S * 0.04), int(cy + H * 1.4)))
    print("icon ok")


if __name__ == "__main__":
    main()
