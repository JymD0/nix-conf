#!/usr/bin/env python3
# Flatten the Framework logo onto the Dracula background color.
# Run this whenever grub-logo.png changes.
# Output overwrites assets/grub-logo.png in place.

from pathlib import Path
from PIL import Image

BG = (40, 42, 54)   # #282a36
FG = (248, 248, 242) # #f8f8f2

repo = Path(__file__).parent.parent
src = repo / "assets" / "grub-logo.png"

img = Image.open(src).convert("RGBA")
w, h = img.size

out = Image.new("RGB", (w, h), BG)
pixels = img.load()
result = out.load()

for y in range(h):
    for x in range(w):
        r, g, b, a = pixels[x, y]
        if a > 0:
            result[x, y] = FG

out.save(src)
print(f"written: {src}")
