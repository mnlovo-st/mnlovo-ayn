#!/usr/bin/env python3
"""Keeps the app's Arabic in Saif's own dialect.

Every word here is one he corrected by hand at some point. Run it before committing:

    python3 tools/wording.py          # list anything off
    python3 tools/wording.py --fix    # rewrite what can be rewritten safely

Words that need a human to pick the form (لسا → بعده / بعدها) are only listed, never rewritten.
A line that has to keep the standard word on purpose (a list of words the app *recognises* in what
people type, say) ends with the comment `wording:ignore`.
"""
import os, re, sys

AR = r'[ء-غـ-يً-ْٰ-ۓ]'
def wb(w): return rf'(?<!{AR}){re.escape(w)}(?!{AR})'

# Whole phrases first, then single words, longest forms before shorter ones.
PHRASES = [
    ("الله لا يبلانا", "لا سمح الله"),
    ("رقم الجوال", "رقم التلفون"),
]
WORDS = [
    ("بكرة", "باجر"), ("بكره", "باجر"),
    ("لحاله", "بنفسه"),
    ("تبيها", "تباها"), ("تبيه", "تباه"), ("تبي", "تبا"),
    ("مين", "منو"),
    ("أرسلنا", "طرشنا"), ("أرسله", "طرشه"), ("أرسلها", "طرشها"), ("أرسل", "طرش"), ("ارسل", "طرش"),
    ("بنرسل", "بنطرش"), ("نرسله", "نطرشه"), ("نرسل", "نطرش"),
    ("ترسله", "تطرشه"), ("ترسل", "تطرش"), ("يرسل", "يطرش"),
    ("تنرسل", "تنطرش"), ("ينرسل", "ينطرش"), ("انرسلت", "انطرشت"), ("انرسل", "انطرش"),
    ("وش", "شو"), ("مو", "مب"), ("جنب", "صوب"),
    ("جوالك", "تلفونك"), ("جوالي", "تلفوني"), ("الجوال", "التلفون"), ("جوال", "تلفون"),
    ("معك", "معاك"),
    ("الجاية", "الياية"), ("الجاي", "الياي"),
    ("كمان", "بعد"), ("شلون", "كيف"),
]
ASK = ["لسا", "لسه"]   # بعده / بعدها depends on the sentence

ROOTS = ["App/Sources", "Widget", "Shared", "supabase"]
EXTS = (".swift", ".ts", ".html")

def files(base):
    for r in ROOTS:
        for d, _, fs in os.walk(os.path.join(base, r)):
            for f in fs:
                if f.endswith(EXTS):
                    yield os.path.join(d, f)

def main():
    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    fix = "--fix" in sys.argv
    found = 0
    for p in files(base):
        src = open(p, encoding="utf-8").read()
        rel = os.path.relpath(p, base)
        lines = src.split("\n")
        for i, line in enumerate(lines):
            if "wording:ignore" in line:
                continue
            for a, b in PHRASES:
                if a in line:
                    found += line.count(a)
                    print(f"{rel}:{i+1}: «{a}» → «{b}»")
                    line = line.replace(a, b)
            for a, b in WORDS:
                n = len(re.findall(wb(a), line))
                if n:
                    found += n
                    print(f"{rel}:{i+1}: «{a}» → «{b}»")
                    line = re.sub(wb(a), b, line)
            for a in ASK:
                if re.search(wb(a), line):
                    found += 1
                    print(f"{rel}:{i+1}: «{a}» — pick بعده or بعدها")
            lines[i] = line
        out = "\n".join(lines)
        if fix and out != src:
            open(p, "w", encoding="utf-8").write(out)
    if not found:
        print("wording: all good")
    sys.exit(1 if found and not fix else 0)

if __name__ == "__main__":
    main()
