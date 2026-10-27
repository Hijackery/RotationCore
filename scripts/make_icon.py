#!/usr/bin/env python3
"""Generate the RotationCore store icon set (512/256/128/64 PNG)."""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 2048
OUT = "docs/icon"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


bg = Image.new("RGBA", (S, S))
db = ImageDraw.Draw(bg)
top, bot = (34, 41, 56), (10, 12, 18)
for y in range(S):
    db.line([(0, y), (S, y)], fill=lerp(top, bot, y / (S - 1)) + (255,))

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
img.paste(bg, (0, 0), rounded_mask(S, int(S * 0.225)))

d = ImageDraw.Draw(img)
d.rounded_rectangle([20, 20, S - 21, S - 21], radius=int(S * 0.215),
                    outline=(196, 141, 40, 255), width=8)

panel = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(panel).rounded_rectangle(
    [86, 86, S - 87, S - 87], radius=int(S * 0.185), fill=(255, 255, 255, 8))
img.alpha_composite(panel)

cx = cy = S / 2
R = int(S * 0.285)
th = int(S * 0.082)
start, end = 38, 322

ring = Image.new("L", (S, S), 0)
dr = ImageDraw.Draw(ring)
dr.arc([cx - R, cy - R, cx + R, cy + R], start=start, end=end, fill=255, width=th)

a = math.radians(end)
px, py = cx + R * math.cos(a), cy + R * math.sin(a)
tx, ty = -math.sin(a), math.cos(a)
rx, ry = math.cos(a), math.sin(a)
L, w = th * 1.65, th * 0.98
tip = (px + tx * L, py + ty * L)
base = (px - tx * th * 0.15, py - ty * th * 0.15)
b1 = (base[0] + rx * w, base[1] + ry * w)
b2 = (base[0] - rx * w, base[1] - ry * w)
dr.polygon([tip, b1, b2], fill=255)

gold_top, gold_bot = (250, 211, 124), (176, 111, 27)
gold = Image.new("RGBA", (S, S))
dg = ImageDraw.Draw(gold)
for y in range(S):
    dg.line([(0, y), (S, y)], fill=lerp(gold_top, gold_bot, y / (S - 1)) + (255,))
img.paste(gold, (0, 0), ring)

hi = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(hi).arc([cx - R, cy - R, cx + R, cy + R], start=start, end=end,
                       fill=(255, 245, 220, 90), width=max(2, th // 5))
img.alpha_composite(hi)

font = ImageFont.truetype(FONT, int(S * 0.32))
txt = "R"
bb = d.textbbox((0, 0), txt, font=font)
tw, tht = bb[2] - bb[0], bb[3] - bb[1]
pos = (cx - tw / 2 - bb[0], cy - tht / 2 - bb[1])

shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).text((pos[0], pos[1] + int(S * 0.012)), txt, font=font, fill=(0, 0, 0, 150))
shadow = shadow.filter(ImageFilter.GaussianBlur(int(S * 0.012)))
img.alpha_composite(shadow)

layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(layer).text(pos, txt, font=font, fill=(246, 242, 232, 255))
img.alpha_composite(layer)

os.makedirs(OUT, exist_ok=True)
for size in (512, 256, 128, 64):
    img.resize((size, size), Image.LANCZOS).save(f"{OUT}/RotationCore-{size}.png")
img.resize((512, 512), Image.LANCZOS).save(f"{OUT}/RotationCore.png")
print("wrote", OUT)
