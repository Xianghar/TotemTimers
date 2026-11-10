"""Generates the textures of the Gamepad totem wheel (GamePad.lua) in textures/:

- wheel_base.tga: the wheel without dividers (outer rim, segment area, inner rim, inner disc), 512 px for 400 UI units
- wheel_divider.tga: a radial divider (vertical bar over the full height), 128 px, rotated in game onto each border
- wheel_highlight<n>.tga (n = 1..8): the highlight wedge of a wheel with n segments, centered at the top, 256 px for
  the whole wheel (400 UI units), rotated in game onto the selected segment

The look follows the Gamepad UI's game menu wheel (atlas gamepad-radial-menu-wheelbg). Plain Python, no
dependencies: python tools/wheel_textures.py
"""
import math
import os
import struct

UI_SIZE = 400.0  # displayed size of the wheel in UI units
R_OUTER = 198.0  # outer edge of the outer rim
R_OUTER_RIM = 188.0  # inner edge of the outer rim
R_INNER_RIM = 66.0  # outer edge of the inner rim
R_INNER = 58.0  # inner edge of the inner rim (inner disc)
DIVIDER_WIDTH = 7.0
SAMPLES = 3  # supersampling per axis

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "textures")


def write_tga(path, size, pixels):
    """pixels: rows top to bottom of (r, g, b, a) floats 0..1, straight alpha"""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    data = bytearray()
    for row in pixels:
        for r, g, b, a in row:
            data += bytes((round(b * 255), round(g * 255), round(r * 255), round(a * 255)))
    with open(path, "wb") as f:
        f.write(header)
        f.write(data)


def render(size, shade):
    """shade(x, y) in UI units relative to the center (y up) -> premultiplied (r, g, b, a) or None"""
    scale = UI_SIZE / size
    rows = []
    for py in range(size):
        row = []
        for px in range(size):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    x = ((px + (sx + 0.5) / SAMPLES) - size / 2) * scale
                    y = (size / 2 - (py + (sy + 0.5) / SAMPLES)) * scale
                    c = shade(x, y)
                    if c:
                        for i in range(4):
                            acc[i] += c[i]
            n = SAMPLES * SAMPLES
            a = acc[3] / n
            if a > 0:
                row.append((acc[0] / n / a, acc[1] / n / a, acc[2] / n / a, a))
            else:
                row.append((0.0, 0.0, 0.0, 0.0))
        rows.append(row)
    return rows


def mix(c1, c2, t):
    return tuple(c1[i] + (c2[i] - c1[i]) * t for i in range(3))


def premul(rgb, a):
    return (rgb[0] * a, rgb[1] * a, rgb[2] * a, a)


def rgb(r, g, b):
    return (r / 255, g / 255, b / 255)


METAL_DARK = rgb(28, 24, 19)
METAL_MID = rgb(92, 84, 70)
METAL_LIGHT = rgb(150, 138, 116)


def metal(t):
    """metallic band across its width, t = 0..1: dark edge, light ridge, dark edge"""
    if t < 0.12 or t > 0.88:
        return METAL_DARK
    if t < 0.45:
        return mix(METAL_MID, METAL_LIGHT, (t - 0.12) / 0.33)
    return mix(METAL_LIGHT, METAL_MID, (t - 0.45) / 0.43)


def base_shade(x, y):
    r = math.hypot(x, y)
    if r > R_OUTER:
        return None
    if r >= R_OUTER_RIM:
        return premul(metal((r - R_OUTER_RIM) / (R_OUTER - R_OUTER_RIM)), 1.0)
    if r >= R_INNER_RIM:
        # segment area: dark, a little lighter toward the inner rim
        t = (r - R_INNER_RIM) / (R_OUTER_RIM - R_INNER_RIM)
        return premul(mix(rgb(46, 31, 20), rgb(20, 13, 9), t), 0.82)
    if r >= R_INNER:
        return premul(metal((r - R_INNER) / (R_INNER_RIM - R_INNER)), 1.0)
    return premul(mix(rgb(40, 27, 18), rgb(24, 16, 11), r / R_INNER), 0.88)


DIVIDER_LENGTH = R_OUTER_RIM - R_INNER_RIM


def divider_shade(x, y):
    # the texture shows DIVIDER_LENGTH UI units, rendered on the UI_SIZE grid of render(): rescale
    x = x * DIVIDER_LENGTH / UI_SIZE
    y = y * DIVIDER_LENGTH / UI_SIZE
    if abs(y) > DIVIDER_LENGTH / 2 or abs(x) > DIVIDER_WIDTH / 2:
        return None
    return premul(metal(x / DIVIDER_WIDTH + 0.5), 1.0)


GLOW = rgb(255, 205, 110)
EDGE_WIDTH = 2.5


def highlight_shade(n):
    half = math.pi / n  # half the segment angle

    def shade(x, y):
        r = math.hypot(x, y)
        if r < R_INNER_RIM or r > R_OUTER_RIM:
            return None
        # angle from the top, clockwise
        angle = math.atan2(x, y)
        if n > 1 and abs(angle) > half:
            return None
        # distance to the wedge outline (rims and, with several segments, the sides)
        edge = min(r - R_INNER_RIM, R_OUTER_RIM - r)
        if n > 1:
            edge = min(edge, r * math.sin(half - abs(angle)))
        if edge < EDGE_WIDTH:
            return premul(GLOW, 0.85)
        # fill: stronger toward the outer rim
        t = (r - R_INNER_RIM) / (R_OUTER_RIM - R_INNER_RIM)
        return premul(GLOW, 0.16 + 0.22 * t)

    return shade


def main():
    os.makedirs(OUT, exist_ok=True)
    write_tga(os.path.join(OUT, "wheel_base.tga"), 512, render(512, base_shade))
    write_tga(os.path.join(OUT, "wheel_divider.tga"), 128, render(128, divider_shade))
    for n in range(1, 9):
        write_tga(os.path.join(OUT, "wheel_highlight%d.tga" % n), 256, render(256, highlight_shade(n)))


if __name__ == "__main__":
    main()
