"""Generates textures/proc_ring.tga: a round version of the action bar's proc glow loop (atlas
UI-HUD-ActionBar-Proc-Loop-Flipbook) for round Gamepad UI buttons, projected from the square glow.

Input: a screenshot of the square glow's sheet shown in game (a 500 x 600 frame with a texture
SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook") over a background SetColorTexture(0.2, 0.2, 0.2), i.e. gray
51/255; 5 columns x 6 rows; the screenshot cut to the gray area, the sheet's area is found as the bounding box of
the gray pixels).

Each of the 30 frames is projected onto a circle: a pixel of the ring takes the color of the point of the square
frame at the same position along the border (arc length on the glow's brightest line, clockwise from the top
center) and at the same distance from the center (scaled from the source frame to 128 px), so the glow and its four
"worms" running along the border keep their shape and speed. The square's corners are rounded: the frame is taken
as the offset of a core square (CORE_HALF of the frame's half size), the normal sweeps around the corners.
The gray background is taken out again: alpha is the least that explains the pixel over gray, the color follows.

Output: 30 frames in 8 columns x 4 rows of 128 px (1024 x 512, the last two cells empty), left to right, top to
bottom, one loop per second in game (AuraDisplay.lua ROUND_GLOW_*). A frame covers 1.4 times the button like the
square glow.

Plain Python, no dependencies: python tools/proc_ring_texture.py <screenshot.png>
"""
import math
import os
import struct
import sys
import zlib

SRC_COLUMNS, SRC_ROWS = 5, 6
FRAMES = SRC_COLUMNS * SRC_ROWS
CELL = 128
COLUMNS, ROWS = 8, 4
SAMPLES = 2  # supersampling per axis
GRAY = 51

# geometry of a source frame as share of its half size (measured on the sheet): the brightest line of the glow and
# the core square whose offsets are the rounded square frames
BAND = 56 / 88.5
CORE_HALF = 42 / 88.5
# the glow lies between 45 and 82 of 88.5: faded in from 0.46 to 0.51, cut after 0.95
INNER_FADE = (0.46, 0.51)
OUTER_END = 0.95

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "textures")


def read_png(path):
    """8 bit RGB or RGBA, not interlaced -> width, height, rows of (r, g, b) tuples"""
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat = 8, b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", body)
            assert depth == 8 and color in (2, 6) and interlace == 0, "unsupported PNG format"
            channels = 3 if color == 2 else 4
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    stride = width * channels
    rows, prev = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for i in range(stride):
            left = line[i - channels] if i >= channels else 0
            up = prev[i]
            upleft = prev[i - channels] if i >= channels else 0
            if kind == 1:
                line[i] = (line[i] + left) & 255
            elif kind == 2:
                line[i] = (line[i] + up) & 255
            elif kind == 3:
                line[i] = (line[i] + (left + up) // 2) & 255
            elif kind == 4:
                p = left + up - upleft
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - upleft)
                pred = left if pa <= pb and pa <= pc else (up if pb <= pc else upleft)
                line[i] = (line[i] + pred) & 255
        rows.append([tuple(line[x * channels:x * channels + 3]) for x in range(width)])
        prev = line
    return width, height, rows


def write_tga(path, width, height, pixels):
    """pixels: rows top to bottom of (r, g, b, a) floats 0..1, straight alpha"""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    data = bytearray()
    for row in pixels:
        for r, g, b, a in row:
            data += bytes((round(b * 255), round(g * 255), round(r * 255), round(a * 255)))
    with open(path, "wb") as f:
        f.write(header)
        f.write(data)


def gray_bounds(width, height, rows):
    """bounding box of the gray background pixels"""
    x0, y0, x1, y1 = width, height, -1, -1
    for y in range(height):
        for x, c in enumerate(rows[y]):
            if c == (GRAY, GRAY, GRAY):
                x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
    return x0, y0, x1 + 1, y1 + 1


def unmix(c):
    """color over gray -> premultiplied rgba with the least alpha (brighter channels need alpha toward white,
    darker ones toward black)"""
    g = GRAY / 255
    a = 0.0
    for v in c:
        v /= 255
        a = max(a, (v - g) / (1 - g) if v > g else (g - v) / g)
    if a <= 0:
        return (0.0, 0.0, 0.0, 0.0)
    # premultiplied color: pixel = color * a + g * (1 - a)
    return tuple(min(a, max(0.0, v / 255 - g * (1 - a))) for v in c) + (a,)


def sample(image, x, y):
    """bilinear on the premultiplied image"""
    ix, iy = int(math.floor(x)), int(math.floor(y))
    fx, fy = x - ix, y - iy
    height, width = len(image), len(image[0])
    acc = [0.0, 0.0, 0.0, 0.0]
    for dy, wy in ((0, 1 - fy), (1, fy)):
        yy = min(max(iy + dy, 0), height - 1)
        for dx, wx in ((0, 1 - fx), (1, fx)):
            w = wx * wy
            if w == 0:
                continue
            c = image[yy][min(max(ix + dx, 0), width - 1)]
            for i in range(4):
                acc[i] += c[i] * w
    return acc


def square_point(u, dist, half):
    """point of the rounded square frame at position u (0..1, clockwise from the top center, arc length on the
    brightest line) and distance dist from the center (along the sides), in px relative to the center, y down"""
    core = CORE_HALF * half
    bend = BAND * half - core  # corner radius of the brightest line
    side = 2 * core
    corner = math.pi / 2 * bend
    # from the top center: half a side, then corner, side, corner, ...; side k: 0 top, 1 right, 2 bottom, 3 left
    s = u * 4 * (side + corner) + core
    k, along, angle = 0, 0.0, None
    while True:
        if s < side or k == 4:
            along = s - core
            break
        s -= side
        if s < corner:
            angle = s / bend
            break
        s -= corner
        k += 1
    k %= 4
    offset = dist - core
    if angle is None:
        px, py = along, -core - offset
    else:
        # corner after side k: the normal turns from up to right (for the top side)
        px, py = core + offset * math.sin(angle), -core - offset * math.cos(angle)
    for _ in range(k):
        px, py = -py, px  # 90 degrees clockwise (y down)
    return px, py


def render_frame(image, cell_x, cell_y, cell_w, cell_h):
    half_src = (cell_w + cell_h) / 4
    center_x, center_y = cell_x + cell_w / 2, cell_y + cell_h / 2
    scale = half_src / (CELL / 2)
    out = []
    for py in range(CELL):
        row = []
        for px in range(CELL):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    x = px + (sx + 0.5) / SAMPLES - CELL / 2
                    y = py + (sy + 0.5) / SAMPLES - CELL / 2
                    r = math.hypot(x, y)
                    # only the glow's ring: inside it the source has stray flecks, beyond it the screenshot's edge
                    share = r * scale / half_src
                    fade = min(1.0, max(0.0, (share - INNER_FADE[0]) / (INNER_FADE[1] - INNER_FADE[0])),
                               max(0.0, (OUTER_END - share) / 0.04))
                    if fade <= 0:
                        continue
                    u = (math.atan2(x, -y) / (2 * math.pi)) % 1.0
                    qx, qy = square_point(u, r * scale, half_src)
                    c = sample(image, center_x + qx, center_y + qy)
                    for i in range(4):
                        acc[i] += c[i] * fade
            n = SAMPLES * SAMPLES
            a = acc[3] / n
            if a > 0.002:
                row.append(tuple(min(1.0, acc[i] / n / a) for i in range(3)) + (a,))
            else:
                row.append((0.0, 0.0, 0.0, 0.0))
        out.append(row)
    return out


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    width, height, rows = read_png(sys.argv[1])
    x0, y0, x1, y1 = gray_bounds(width, height, rows)
    cell_w, cell_h = (x1 - x0) / SRC_COLUMNS, (y1 - y0) / SRC_ROWS
    print("sheet %d,%d - %d,%d, frames %.1f x %.1f px" % (x0, y0, x1, y1, cell_w, cell_h))
    image = [[unmix(c) for c in row] for row in rows]
    sheet = [[(0.0, 0.0, 0.0, 0.0)] * (CELL * COLUMNS) for _ in range(CELL * ROWS)]
    for i in range(FRAMES):
        frame = render_frame(image, x0 + (i % SRC_COLUMNS) * cell_w, y0 + (i // SRC_COLUMNS) * cell_h,
                             cell_w, cell_h)
        column, row = i % COLUMNS, i // COLUMNS
        for py in range(CELL):
            sheet[row * CELL + py][column * CELL:(column + 1) * CELL] = frame[py]
    os.makedirs(OUT, exist_ok=True)
    write_tga(os.path.join(OUT, "proc_ring.tga"), CELL * COLUMNS, CELL * ROWS, sheet)


if __name__ == "__main__":
    main()
