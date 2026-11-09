"""Generates the AYN app icon, asset catalog and UI sound effects.
Re-run any time: python3 tools/make_assets.py
Sounds are soft synthesized placeholders — replace any .wav in App/Resources/Sounds
with your own composition using the same file name.
"""
import json, math, os, wave
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "App", "Resources")
XC = os.path.join(RES, "Assets.xcassets")
SR = 44100

# ---------------------------------------------------------------- assets
def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)

def color_set(name, r, g, b):
    write_json(os.path.join(XC, f"{name}.colorset", "Contents.json"), {
        "colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {
            "red": f"{r/255:.3f}", "green": f"{g/255:.3f}", "blue": f"{b/255:.3f}", "alpha": "1.000"}}}],
        "info": {"author": "xcode", "version": 1}})

def make_icon():
    S = 1024
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    # deep night background with a soft aurora glow
    bg = np.zeros((S, S, 3), np.float32)
    bg[..., 0], bg[..., 1], bg[..., 2] = 7, 8, 14
    def glow(cx, cy, rad, col, k):
        d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / rad
        a = np.clip(1 - d, 0, 1) ** 2 * k
        for i in range(3):
            bg[..., i] += a * col[i]
    glow(300, 260, 700, (57, 230, 200), 0.55)
    glow(760, 820, 720, (123, 108, 255), 0.65)
    img = Image.fromarray(np.clip(bg, 0, 255).astype(np.uint8), "RGB").convert("RGBA")

    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy, w, h = S / 2, S / 2, 760, 420
    # almond eye outline via polygon from two quadratic curves
    pts_top, pts_bot = [], []
    for t in np.linspace(0, 1, 120):
        px = (1 - t) ** 2 * (cx - w / 2) + 2 * (1 - t) * t * cx + t ** 2 * (cx + w / 2)
        pyt = (1 - t) ** 2 * cy + 2 * (1 - t) * t * (cy - h) + t ** 2 * cy
        pyb = (1 - t) ** 2 * cy + 2 * (1 - t) * t * (cy + h) + t ** 2 * cy
        pts_top.append((px, pyt)); pts_bot.append((px, pyb))
    almond = pts_top + pts_bot[::-1]
    glow_l = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow_l).line(almond + [almond[0]], fill=(57, 230, 200, 255), width=38)
    glow_l = glow_l.filter(ImageFilter.GaussianBlur(28))
    img = Image.alpha_composite(img, glow_l)
    d.polygon(almond, fill=(240, 244, 255, 245))
    # iris: angular gradient teal/indigo
    R = 175
    iris = np.zeros((S, S, 4), np.float32)
    ang = (np.arctan2(y - cy, x - cx) + math.pi) / (2 * math.pi)
    mix = (np.sin(ang * math.pi * 4) + 1) / 2
    c1, c2 = np.array([57, 230, 200]), np.array([123, 108, 255])
    for i in range(3):
        iris[..., i] = c1[i] * mix + c2[i] * (1 - mix)
    dist = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
    iris[..., 3] = np.where(dist < R, 255, 0)
    shade = np.clip(1 - (dist / R) ** 6 * 0.6, 0, 1)
    for i in range(3):
        iris[..., i] *= shade
    iris_img = Image.fromarray(iris.astype(np.uint8), "RGBA")
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(almond, fill=255)
    layer = Image.alpha_composite(layer, Image.composite(iris_img, Image.new("RGBA", (S, S)), mask))
    d = ImageDraw.Draw(layer)
    d.ellipse((cx - 72, cy - 72, cx + 72, cy + 72), fill=(5, 6, 10, 255))
    d.ellipse((cx - 95, cy - 110, cx - 40, cy - 55), fill=(255, 255, 255, 235))
    d.ellipse((cx + 40, cy + 40, cx + 64, cy + 64), fill=(255, 255, 255, 140))
    d.line(almond + [almond[0]], fill=(57, 230, 200, 255), width=14)
    img = Image.alpha_composite(img, layer).convert("RGB")
    path = os.path.join(XC, "AppIcon.appiconset")
    os.makedirs(path, exist_ok=True)
    img.save(os.path.join(path, "icon-1024.png"))
    write_json(os.path.join(path, "Contents.json"), {
        "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1}})
    img.resize((256, 256)).save(os.path.join(ROOT, "tools", "icon-preview.png"))

def make_catalog():
    write_json(os.path.join(XC, "Contents.json"), {"info": {"author": "xcode", "version": 1}})
    color_set("AccentColor", 57, 230, 200)
    color_set("LaunchBG", 7, 8, 13)
    make_icon()

# ---------------------------------------------------------------- sounds
def env(n, a=0.005, r=0.2):
    t = np.arange(n) / SR
    e = np.minimum(1, t / max(a, 1e-4))
    return e * np.exp(-t / max(r, 1e-4))

def tone(freq, dur, a=0.005, r=0.2, harm=(1.0, 0.25, 0.08), detune=0.0):
    n = int(SR * dur); t = np.arange(n) / SR
    s = np.zeros(n)
    for k, amp in enumerate(harm, start=1):
        s += amp * np.sin(2 * math.pi * freq * k * t * (1 + detune * k))
    return s * env(n, a, r)

def bell(freq, dur, r=0.5):
    n = int(SR * dur); t = np.arange(n) / SR
    s = (np.sin(2 * math.pi * freq * t) + 0.35 * np.sin(2 * math.pi * freq * 2.76 * t) * np.exp(-t / (r * 0.3))
         + 0.18 * np.sin(2 * math.pi * freq * 5.4 * t) * np.exp(-t / (r * 0.15)))
    return s * env(n, 0.002, r)

def noise(dur, lp=0.05):
    n = int(SR * dur); w = np.random.default_rng(7).normal(0, 1, n)
    out = np.zeros(n); acc = 0.0
    for i in range(n):  # one-pole low-pass
        acc += lp * (w[i] - acc); out[i] = acc
    return out / (np.max(np.abs(out)) + 1e-9)

def place(buf, s, at):
    i = int(at * SR); j = min(len(buf), i + len(s)); buf[i:j] += s[: j - i]; return buf

def reverb(s, mix=0.25):
    out = s.copy()
    for d, g in ((0.031, 0.5), (0.047, 0.42), (0.067, 0.35), (0.089, 0.28), (0.113, 0.2)):
        k = int(d * SR); tmp = np.zeros(len(s) + k); tmp[k:] = s * g; out = out + mix * tmp[: len(s)]
    return out

def save(name, s, gain=0.8, tail=0.15):
    s = np.concatenate([s, np.zeros(int(SR * tail))])
    s = reverb(s, 0.22)
    s = s / (np.max(np.abs(s)) + 1e-9) * gain
    fade = int(SR * 0.01); s[-fade:] *= np.linspace(1, 0, fade)
    data = (s * 32767).astype(np.int16)
    with wave.open(os.path.join(RES, "Sounds", name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())

def make_sounds():
    os.makedirs(os.path.join(RES, "Sounds"), exist_ok=True)
    save("tap", tone(1760, 0.06, 0.001, 0.02, (1, 0.1)) + 0.3 * noise(0.06, 0.3) * env(int(SR * 0.06), 0.001, 0.008), 0.35, 0.02)
    save("type", tone(2400, 0.03, 0.0005, 0.008, (1,)) * 0.8, 0.22, 0.01)
    save("toggle", np.concatenate([tone(880, 0.05, 0.002, 0.03), tone(1320, 0.08, 0.002, 0.04)]), 0.4, 0.05)
    s = np.zeros(int(SR * 0.9))
    for i, f in enumerate((1046.5, 1318.5, 1568.0, 2093.0)):
        place(s, bell(f, 0.8, 0.35) * (0.9 - i * 0.12), i * 0.07)
    save("success", s, 0.6)
    s = np.zeros(int(SR * 0.5)); place(s, tone(330, 0.25, 0.005, 0.12, (1, 0.5, 0.2)), 0); place(s, tone(262, 0.3, 0.005, 0.15, (1, 0.5, 0.2)), 0.11)
    save("error", s, 0.55)
    n = int(SR * 0.6); t = np.arange(n) / SR
    sweep = np.sin(2 * math.pi * (400 * t + 500 * t * t / 0.6 / 2 * 2)) * env(n, 0.05, 0.18)
    s = sweep * 0.5; place(s, bell(1568, 0.5, 0.3) * 0.7, 0.18)
    save("unlock", s, 0.6)
    s = tone(220, 0.35, 0.002, 0.08, (1, 0.6, 0.3)) + 0.4 * noise(0.35, 0.08) * env(int(SR * 0.35), 0.001, 0.03)
    save("lock", s, 0.5)
    nz = noise(0.7, 0.04); s = nz * np.hanning(len(nz)) * 0.6; place(s, bell(2349, 0.5, 0.25) * 0.35, 0.38)
    save("eye_open", s, 0.45)
    save("blink", tone(1975, 0.05, 0.001, 0.015, (1, 0.2)), 0.18, 0.02)
    nz = noise(0.35, 0.15); save("delete", nz * np.hanning(len(nz)), 0.35, 0.05)
    s = np.zeros(int(SR * 1.4))
    for i, f in enumerate((1318.5, 1760.0, 2217.5)):
        place(s, bell(f, 1.1, 0.45) * (1 - i * 0.15), i * 0.16)
    save("notify", s, 0.75)
    # intro: soft pad (A minor 9) + boom when the eye opens + shimmer
    dur = 2.8; n = int(SR * dur); t = np.arange(n) / SR
    pad = np.zeros(n)
    for f in (110.0, 164.8, 220.0, 261.6, 329.6, 493.9):
        pad += np.sin(2 * math.pi * f * t + 0.3 * np.sin(2 * math.pi * 0.25 * t)) * (0.5 if f < 200 else 0.25)
    pad *= np.minimum(1, t / 0.9) * np.clip((dur - t) / 1.2, 0, 1)
    s = pad * 0.45
    boom = tone(55, 1.2, 0.01, 0.4, (1, 0.4)); place(s, boom * 0.9, 0.75)
    nz = noise(1.0, 0.03); place(s, nz * np.hanning(len(nz)) * 0.3, 0.3)
    for i, f in enumerate((1760.0, 2093.0, 2637.0, 3520.0)):
        place(s, bell(f, 1.0, 0.4) * 0.25, 0.9 + i * 0.09)
    save("intro", s, 0.7, 0.3)

if __name__ == "__main__":
    make_catalog()
    make_sounds()
    print("assets ok")
