"""Generates textures/excluded.tga: a red prohibition sign (circle with a diagonal line from the top left to the
bottom right) with a dark outline, transparent inside. It marks a totem timer excluded from the active multicast
spell (TotemTimers.CreateExcludedIcon in SetupTimers.lua), on the timer buttons and the Gamepad UI bar slots.

Plain Python, no dependencies: python tools/excluded_texture.py
"""
import math
import os
import struct

SIZE = 64  # texture size in pixels
SAMPLES = 4  # supersampling per axis

# in units of the texture's half size (1 = edge)
R_OUTER = 0.92  # outer edge of the red ring
R_INNER = 0.66  # inner edge of the red ring
BAR_HALF_WIDTH = 0.13  # half width of the red diagonal bar
OUTLINE = 0.07  # width of the dark outline around the red shape

RED = (0.70, 0.05, 0.04)
DARK = (0.0, 0.0, 0.0)
DARK_ALPHA = 0.85

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "textures", "excluded.tga")


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


def distance_to_sign(x, y):
    """signed distance to the red shape (negative inside): the ring united with the bar inside the ring"""
    r = math.hypot(x, y)
    ring = max(R_INNER - r, r - R_OUTER)
    # bar from the top left to the bottom right (y up): along the direction (1, -1), clipped to the inner disc
    along_normal = abs(x + y) / math.sqrt(2)
    bar = max(along_normal - BAR_HALF_WIDTH, r - R_INNER)
    return min(ring, bar)


def shade(x, y):
    """premultiplied (r, g, b, a) at a point, or None"""
    d = distance_to_sign(x, y)
    if d <= 0:
        return (RED[0], RED[1], RED[2], 1.0)
    if d <= OUTLINE:
        return (DARK[0] * DARK_ALPHA, DARK[1] * DARK_ALPHA, DARK[2] * DARK_ALPHA, DARK_ALPHA)
    return None


def render(size):
    rows = []
    for py in range(size):
        row = []
        for px in range(size):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    x = (px + (sx + 0.5) / SAMPLES) / size * 2 - 1
                    y = 1 - (py + (sy + 0.5) / SAMPLES) / size * 2
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


if __name__ == "__main__":
    write_tga(OUT, SIZE, render(SIZE))
    print("wrote " + os.path.normpath(OUT))
