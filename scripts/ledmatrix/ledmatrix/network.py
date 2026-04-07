import argparse
import math
import time
from ledmatrix import Matrix, ROWS, COLS


def _arc_pixels(origin_r, origin_c, radius):
    px = []
    for r in range(ROWS):
        for c in range(COLS):
            d = math.sqrt((r - origin_r) ** 2 + (c - origin_c) ** 2)
            if abs(d - radius) < 0.8:
                px.append((r, c))
    return px


def _animate_arcs(dev, radii, origin_r, origin_c, reverse=False):
    FADE = [255, 180, 90, 20, 0]
    FRAME_MS = 0.1

    arc_pixels = [_arc_pixels(origin_r, origin_c, r) for r in radii]
    if reverse:
        arc_pixels = list(reversed(arc_pixels))

    total_frames = len(radii) + len(FADE) - 1

    for frame in range(total_frames):
        m = Matrix()
        for arc_i, px in enumerate(arc_pixels):
            fade_idx = frame - arc_i
            if 0 <= fade_idx < len(FADE):
                b = FADE[fade_idx]
                for r, c in px:
                    m.set(r, c, b)
        m.send(dev)
        time.sleep(FRAME_MS)

    if reverse:
        for _ in range(2):
            m = Matrix()
            m.set(min(origin_r, ROWS - 1), min(origin_c, COLS - 1), 255)
            m.send(dev)
            time.sleep(0.15)
            Matrix().send(dev)
            time.sleep(0.15)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("direction", choices=["up", "down"])
    parser.add_argument("--mode", choices=["wifi", "vpn"], default="wifi")
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    if args.mode == "wifi":
        origin_r, origin_c = 0, 4   # top edge, horizontal center
    else:
        origin_r, origin_c = 17, 4  # vertical center

    radii = [4, 8, 12, 16]
    _animate_arcs(args.dev, radii, origin_r, origin_c, reverse=(args.direction == "down"))
