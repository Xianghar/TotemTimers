"""Generates textures/lightning_bar.tga, the bar texture of the Maelstrom tracker (CombatCDs.lua).

In the style of the Lightning Bolt icon (spell_nature_lightning): a dark, stormy indigo/blue background and a bright
white-blue jagged bolt with a blue glow, but without the icon's border and drawn for the bar's shape. The bolt runs
horizontally over the whole width, so the filling bar (stacks) shows more of it.

The image is drawn for a displayed aspect ratio of ASPECT:1 (the bar: about 108-176 x 19-27 UI units) and stored as
512 x 64 pixels (power of two sizes), so in game it isn't stretched. Opaque, no border.
Plain Python, no dependencies: python tools/lightning_texture.py
"""
import math
import os
import random
import struct

WIDTH, HEIGHT = 512, 64  # pixels
ASPECT = 6.0  # displayed width / height; drawing units: x 0..ASPECT, y 0..1 (y down)
SAMPLES = 2  # supersampling per axis
SEED = 42  # chosen so the main bolt runs around the middle (as many points above as below)

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "textures", "lightning_bar.tga")


def write_tga(path, width, height, pixels):
    """pixels: rows top to bottom of (r, g, b) floats 0..1, opaque"""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    data = bytearray()
    for row in pixels:
        for r, g, b in row:
            data += bytes((clamp8(b), clamp8(g), clamp8(r), 255))
    with open(path, "wb") as f:
        f.write(header)
        f.write(data)


def clamp8(v):
    return max(0, min(255, round(v * 255)))


def mix(c1, c2, t):
    return tuple(a + (b - a) * t for a, b in zip(c1, c2))


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


# value noise for the storm clouds of the background
rng = random.Random(SEED)
GRID = {}


def lattice(ix, iy):
    key = (ix, iy)
    if key not in GRID:
        GRID[key] = rng.random()
    return GRID[key]


def value_noise(x, y):
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    top = lattice(ix, iy) + (lattice(ix + 1, iy) - lattice(ix, iy)) * sx
    bottom = lattice(ix, iy + 1) + (lattice(ix + 1, iy + 1) - lattice(ix, iy + 1)) * sx
    return top + (bottom - top) * sy


def clouds(x, y):
    total, amp, freq = 0.0, 0.5, 2.0
    for _ in range(4):
        total += value_noise(x * freq, y * freq) * amp
        amp *= 0.5
        freq *= 2.0
    return total


# the bolt: midpoint displacement (each segment's midpoint is moved sideways by a random amount proportional to the
# segment's length, recursively), a main bolt from the left to the right edge and a few forks that taper off
def lightning(start, end, depth, roughness, bounds):
    points = [start, end]
    for _ in range(depth):
        refined = [points[0]]
        for a, b in zip(points, points[1:]):
            dx, dy = b[0] - a[0], b[1] - a[1]
            length = math.hypot(dx, dy)
            # perpendicular offset
            offset = rng.uniform(-roughness, roughness) * length
            mx = (a[0] + b[0]) / 2 - dy / length * offset
            my = (a[1] + b[1]) / 2 + dx / length * offset
            my = max(bounds[0], min(bounds[1], my))
            refined += [(mx, my), b]
        points = refined
    return points


main_path = lightning((-0.1, 0.5), (ASPECT + 0.1, 0.5), 7, 0.17, (0.27, 0.73))

SEGMENTS = [(a, b, 1.0) for a, b in zip(main_path, main_path[1:])]
for i in range(10, len(main_path) - 12, 19):
    bx, by = main_path[i]
    up = -1 if by > 0.5 else 1
    target = (bx + rng.uniform(0.45, 0.8), max(0.04, min(0.96, by + up * rng.uniform(0.3, 0.42))))
    fork = lightning((bx, by), target, 5, 0.3, (0.02, 0.98))
    # tapering: thinner and dimmer toward the tip
    for k, (a, b) in enumerate(zip(fork, fork[1:])):
        SEGMENTS.append((a, b, 0.65 * (1 - k / len(fork)) + 0.15))


def segment_distance(p, a, b):
    ax, ay = a
    bx, by = b
    px, py = p
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    cx, cy = ax + t * dx, ay + t * dy
    return math.hypot(px - cx, py - cy)


DARK = (0.03, 0.03, 0.14)
STORM = (0.20, 0.14, 0.52)
HAZE = (0.30, 0.38, 0.85)
GLOW = (0.35, 0.65, 1.00)
CORE = (0.92, 0.97, 1.00)


def shade(x, y):
    # background: storm clouds, darker toward the top and bottom edges (no border)
    cloud = clouds(x, y)
    edge = 1.0 - 0.55 * abs(y - 0.5) * 2
    color = mix(DARK, STORM, smoothstep(0.25, 0.75, cloud) * edge)

    # bolt: thin white core, blue glow around it (branches thinner and dimmer)
    core, glow = 0.0, 0.0
    for a, b, weight in SEGMENTS:
        # skip segments far away (speed)
        if x < min(a[0], b[0]) - 0.5 or x > max(a[0], b[0]) + 0.5:
            continue
        d = segment_distance((x, y), a, b)
        core = max(core, weight * (1.0 - smoothstep(0.012 * weight + 0.006, 0.035 * weight + 0.012, d)))
        glow = max(glow, weight * math.exp(-d / (0.11 * weight + 0.02)))

    color = mix(color, HAZE, glow * 0.45)
    color = mix(color, GLOW, glow * 0.55)
    return mix(color, CORE, core)


def main():
    rows = []
    for py in range(HEIGHT):
        row = []
        for px in range(WIDTH):
            acc = [0.0, 0.0, 0.0]
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    x = (px + (sx + 0.5) / SAMPLES) / WIDTH * ASPECT
                    y = (py + (sy + 0.5) / SAMPLES) / HEIGHT
                    c = shade(x, y)
                    for i in range(3):
                        acc[i] += c[i]
            n = SAMPLES * SAMPLES
            row.append((acc[0] / n, acc[1] / n, acc[2] / n))
        rows.append(row)
    write_tga(OUT, WIDTH, HEIGHT, rows)
    print("wrote", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
