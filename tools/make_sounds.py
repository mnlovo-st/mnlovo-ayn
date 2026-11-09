"""MNLOVO SAVER — sound design.

A small, coherent sound set built around a plucked "qanun-like" string (Karplus–Strong with
three detuned courses), soft glass bells, a warm pad and airy whooshes, all placed in a
stereo hall reverb. Melodic material uses maqam Hijaz on D (D Eb F# G A Bb C).

Run:  python3 tools/make_sounds.py   → App/Resources/Sounds/*.wav (48 kHz, 16-bit, stereo)
Replace any file with your own composition using the same name.
"""
import math, os, wave
import numpy as np
from scipy import signal

SR = 48000
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "App", "Resources", "Sounds")
rng = np.random.default_rng(2026)

N = {"D3": 146.83, "A3": 220.00, "D4": 293.66, "Eb4": 311.13, "F#4": 369.99, "G4": 392.00,
     "A4": 440.00, "Bb4": 466.16, "C5": 523.25, "D5": 587.33, "Eb5": 622.25, "F#5": 739.99,
     "G5": 783.99, "A5": 880.00, "D6": 1174.66, "F#6": 1479.98, "A6": 1760.0}


def secs(d):
    return int(round(d * SR))


# ------------------------------------------------------------------ voices

def ks_string(freq, dur, decay=0.996, bright=0.55, detune_cents=0.0):
    """Karplus–Strong string with fractional delay and a soft (low-passed) excitation."""
    n = secs(dur)
    f = freq * (2 ** (detune_cents / 1200))
    delay = SR / f
    di = int(delay)
    frac = delay - di
    buf_len = di + 2
    exc = rng.uniform(-1, 1, buf_len)
    b, a = signal.butter(2, min(0.99, bright * 0.6 + 0.05))
    exc = signal.lfilter(b, a, exc)
    out = np.zeros(n)
    hist = np.zeros(n + buf_len)
    hist[:buf_len] = exc
    for i in range(n):
        j = i + buf_len
        p1 = hist[j - di] * (1 - frac) + hist[j - di - 1] * frac
        p2 = hist[j - di - 1] * (1 - frac) + hist[j - di - 2] * frac if j - di - 2 >= 0 else 0.0
        v = decay * 0.5 * (p1 + p2)
        hist[j] = v
        out[i] = v
    return out


def pluck(freq, dur=1.6, decay=0.996, bright=0.55, body=0.35):
    """Three detuned courses (like a qanun) + a soft sine body for warmth."""
    s = (ks_string(freq, dur, decay, bright, -3) + ks_string(freq, dur, decay, bright, 0)
         + ks_string(freq, dur, decay, bright, +3.5)) / 3
    t = np.arange(len(s)) / SR
    s += body * np.sin(2 * np.pi * freq * t) * np.exp(-t * 5.5) * np.minimum(1, t / 0.004)
    return s / (np.max(np.abs(s)) + 1e-9)


def bell(freq, dur=1.8, index=1.6, ratio=2.76, decay=2.6):
    """Soft FM glass bell."""
    t = np.arange(secs(dur)) / SR
    env = np.minimum(1, t / 0.003) * np.exp(-t * decay)
    mod = index * np.exp(-t * 4.0) * np.sin(2 * np.pi * freq * ratio * t)
    s = np.sin(2 * np.pi * freq * t + mod) * env
    s += 0.18 * np.sin(2 * np.pi * freq * 2.0 * t) * np.exp(-t * decay * 1.8)
    return s / (np.max(np.abs(s)) + 1e-9)


def pad(freqs, dur, attack=0.9, release=1.2):
    t = np.arange(secs(dur)) / SR
    s = np.zeros_like(t)
    for f in freqs:
        for det in (-0.12, 0.0, 0.11):
            ff = f * (1 + det / 100)
            for h, amp in ((1, 1.0), (2, 0.32), (3, 0.12), (4, 0.05)):
                s += amp * np.sin(2 * np.pi * ff * h * t + rng.uniform(0, 6.28))
    vib = 1 + 0.08 * np.sin(2 * np.pi * 0.23 * t)
    env = np.minimum(1, t / attack) * np.clip((dur - t) / release, 0, 1)
    s = s * env * vib
    b, a = signal.butter(2, 2600 / (SR / 2))
    s = signal.lfilter(b, a, s)
    return s / (np.max(np.abs(s)) + 1e-9)


def whoosh(dur, lo=300, hi=3200, rise=True):
    """Airy band-passed noise with a moving centre frequency."""
    n = secs(dur)
    noise = rng.normal(0, 1, n)
    out = np.zeros(n)
    blocks = 24
    edges = np.linspace(0, n, blocks + 1).astype(int)
    for k in range(blocks):
        x = k / (blocks - 1)
        c = lo * (hi / lo) ** (x if rise else 1 - x)
        bw = c * 0.9
        low, high = max(40, c - bw / 2), min(SR / 2 - 100, c + bw / 2)
        b, a = signal.butter(2, [low / (SR / 2), high / (SR / 2)], btype="band")
        seg = signal.lfilter(b, a, noise)
        out[edges[k]:edges[k + 1]] = seg[edges[k]:edges[k + 1]]
    env = np.sin(np.linspace(0, np.pi, n)) ** 1.6
    out = out * env
    return out / (np.max(np.abs(out)) + 1e-9)


def bloom(dur=1.2, f0=82, f1=55):
    """Soft sub 'bloom' for the moment the eye opens."""
    t = np.arange(secs(dur)) / SR
    f = f1 + (f0 - f1) * np.exp(-t * 6)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) * np.minimum(1, t / 0.02) * np.exp(-t * 3.2)


def muted(s, cutoff=1400):
    b, a = signal.butter(2, cutoff / (SR / 2))
    return signal.lfilter(b, a, s)


# ------------------------------------------------------------------ mixing

class Mix:
    def __init__(self, dur):
        self.buf = np.zeros((secs(dur), 2))

    def add(self, s, at=0.0, gain=1.0, pan=0.0):
        s = np.array(s, dtype=float)
        fo = min(len(s), secs(0.06))                  # every voice ends with a soft fade (no clicks)
        s[-fo:] *= np.linspace(1, 0, fo) ** 2
        i = secs(at)
        if i + len(s) > len(self.buf):                # grow instead of truncating
            self.buf = np.vstack([self.buf, np.zeros((i + len(s) - len(self.buf), 2))])
        j = i + len(s)
        l = math.cos((pan + 1) * math.pi / 4)
        r = math.sin((pan + 1) * math.pi / 4)
        self.buf[i:j, 0] += s[: j - i] * gain * l
        self.buf[i:j, 1] += s[: j - i] * gain * r
        return self


def hall_ir(length=2.4, predelay=0.018, damp=4200):
    n = secs(length)
    t = np.arange(n) / SR
    ir = np.zeros((n, 2))
    for ch in range(2):
        noise = rng.normal(0, 1, n)
        b, a = signal.butter(1, damp / (SR / 2))
        noise = signal.lfilter(b, a, noise)
        ir[:, ch] = noise * np.exp(-t * (6.9 / length))
    pd = secs(predelay)
    ir = np.vstack([np.zeros((pd, 2)), ir])
    # a few early reflections for space
    for d, g in ((0.011, 0.5), (0.019, 0.35), (0.027, 0.28), (0.041, 0.2)):
        k = secs(d)
        ir[k, 0] += g
        ir[k + 7, 1] += g * 0.9
    return ir / np.sqrt(np.sum(ir ** 2) / 2)


IR = hall_ir()
IR_LONG = hall_ir(3.6, 0.025, 3600)


def master(m, wet=0.28, long=False, tail=0.6, peak_db=-3.0, highpass=60):
    dry = np.vstack([m.buf, np.zeros((secs(tail), 2))])
    ir = IR_LONG if long else IR
    wet_sig = np.stack([signal.fftconvolve(dry[:, c], ir[:, c])[: len(dry)] for c in range(2)], axis=1)
    out = dry * (1 - wet * 0.5) + wet_sig * wet * 0.35
    b, a = signal.butter(2, highpass / (SR / 2), btype="high")
    out = signal.lfilter(b, a, out, axis=0)
    out = np.tanh(out / (np.max(np.abs(out)) + 1e-9) * 1.2)       # gentle glue / soft-clip
    out = out / (np.max(np.abs(out)) + 1e-9) * (10 ** (peak_db / 20))
    fi = secs(0.004)
    out[:fi] *= np.linspace(0, 1, fi)[:, None]
    fo = secs(min(0.25, tail * 0.8))
    out[-fo:] *= np.linspace(1, 0, fo)[:, None] ** 2
    return out


def save(name, data):
    os.makedirs(OUT, exist_ok=True)
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# ------------------------------------------------------------------ the set

def make_all():
    for f in os.listdir(OUT) if os.path.isdir(OUT) else []:
        if f.endswith(".wav"):
            os.remove(os.path.join(OUT, f))

    # Intro — warm pad, the eye "blooms" open, Hijaz motif rises across the stereo field.
    m = Mix(3.0)
    m.add(pad([N["D3"], N["A3"], N["D4"]], 3.0, attack=1.0, release=1.4), 0, 0.42)
    m.add(bloom(1.4), 0.5, 0.7)
    m.add(whoosh(1.1, 250, 2600), 0.15, 0.22)
    for k, (note, pan) in enumerate((("D5", -0.5), ("Eb5", -0.2), ("F#5", 0.15), ("A5", 0.45))):
        m.add(pluck(N[note], 1.8, 0.9965, 0.5), 0.72 + k * 0.17, 0.55 - k * 0.04, pan)
    m.add(bell(N["D6"], 2.2, 1.2, 2.0, 1.9), 1.5, 0.22, 0.1)
    save("intro", master(m, wet=0.42, long=True, tail=1.2, peak_db=-2.5))

    # Unlock — two rising plucks + a soft glass shimmer.
    m = Mix(1.2)
    m.add(pluck(N["A4"], 1.2, 0.995, 0.5), 0.0, 0.6, -0.25)
    m.add(pluck(N["D5"], 1.2, 0.995, 0.55), 0.085, 0.65, 0.25)
    m.add(bell(N["D6"], 1.2, 1.0, 2.0, 3.2), 0.13, 0.16, 0.0)
    m.add(whoosh(0.35, 900, 5000), 0.0, 0.05)
    save("unlock", master(m, wet=0.3, tail=0.6, peak_db=-4))

    # Lock — muted descending pair with a soft low thump.
    m = Mix(0.6)
    m.add(muted(pluck(N["D5"], 0.6, 0.99, 0.35), 1600), 0.0, 0.6, 0.15)
    m.add(muted(pluck(N["A4"], 0.6, 0.99, 0.3), 1300), 0.07, 0.6, -0.15)
    m.add(bloom(0.35, 110, 70), 0.0, 0.35)
    save("lock", master(m, wet=0.18, tail=0.35, peak_db=-6))

    # Success — bright Hijaz arpeggio with a sparkle on top.
    m = Mix(1.5)
    for k, (note, pan) in enumerate((("D5", -0.4), ("F#5", -0.1), ("A5", 0.2), ("D6", 0.45))):
        m.add(pluck(N[note], 1.4, 0.9955, 0.6), k * 0.075, 0.6, pan)
    m.add(bell(N["A6"], 1.2, 0.8, 2.0, 3.0), 0.3, 0.1, 0.3)
    save("success", master(m, wet=0.32, tail=0.7, peak_db=-4))

    # Error — gentle "hmm": the Hijaz half-step falling (Eb → D), muted and low.
    m = Mix(0.7)
    m.add(muted(pluck(N["Eb4"], 0.7, 0.993, 0.35), 1100), 0.0, 0.7, -0.1)
    m.add(muted(pluck(N["D4"], 0.8, 0.993, 0.35), 1000), 0.12, 0.75, 0.1)
    save("error", master(m, wet=0.2, tail=0.4, peak_db=-6))

    # Eye opening — breath + a tiny glint.
    m = Mix(0.9)
    m.add(whoosh(0.7, 200, 2400), 0.0, 0.5)
    m.add(bell(N["D6"], 0.9, 0.7, 2.0, 4.0), 0.42, 0.18, 0.2)
    save("eye_open", master(m, wet=0.35, tail=0.5, peak_db=-8))

    # Notification — friendly three-note call that cuts through without being harsh.
    m = Mix(1.8)
    for k, (note, pan) in enumerate((("A5", -0.25), ("F#5", 0.0), ("D6", 0.25))):
        m.add(pluck(N[note], 1.6, 0.9965, 0.62), k * 0.14, 0.7, pan)
    m.add(bell(N["D6"], 1.6, 1.0, 2.0, 2.2), 0.3, 0.18)
    save("notify", master(m, wet=0.3, tail=0.6, peak_db=-1.5))

    # Delete — soft downward swipe.
    m = Mix(0.45)
    m.add(whoosh(0.4, 3500, 400, rise=True), 0.0, 0.6)
    save("delete", master(m, wet=0.15, tail=0.2, peak_db=-10))


if __name__ == "__main__":
    make_all()
    print("sounds:", sorted(os.listdir(OUT)))
