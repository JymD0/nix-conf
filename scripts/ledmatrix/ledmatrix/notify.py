import argparse
import time
from ledmatrix import Matrix, ROWS, COLS

# 7 wide x 5 tall envelope outline, top-left at (14, 1)
_ENV_R = 14
_ENV_C = 1
_ENV_H = 5
_ENV_W = 7

# flap V: row 14 cols 1-7, rows 15-16 diagonals
_ENVELOPE = []
# top edge
for c in range(_ENV_C, _ENV_C + _ENV_W):
    _ENVELOPE.append((_ENV_R, c))
# bottom edge
for c in range(_ENV_C, _ENV_C + _ENV_W):
    _ENVELOPE.append((_ENV_R + _ENV_H - 1, c))
# left and right edges
for r in range(_ENV_R + 1, _ENV_R + _ENV_H - 1):
    _ENVELOPE.append((r, _ENV_C))
    _ENVELOPE.append((r, _ENV_C + _ENV_W - 1))
# flap diagonals (V shape from top corners to center)
_ENVELOPE.append((_ENV_R + 1, _ENV_C + 1))
_ENVELOPE.append((_ENV_R + 1, _ENV_C + 5))
_ENVELOPE.append((_ENV_R + 2, _ENV_C + 3))

# 3 wide x 7 tall question mark, top-left at (14, 3)
_QM_R = 14
_QM_C = 3
_QMARK = [
    (_QM_R,     _QM_C + 0), (_QM_R,     _QM_C + 1),
    (_QM_R + 1, _QM_C + 2),
    (_QM_R + 2, _QM_C + 1),
    (_QM_R + 3, _QM_C + 1),
    # gap at row +4
    (_QM_R + 5, _QM_C + 1),
]


def _draw(dev, pixels, duration_ms):
    m = Matrix()
    for r, c in pixels:
        m.set(r, c, 255)
    m.send(dev)

    time.sleep(duration_ms / 1000)

    for b in [180, 100, 30, 0]:
        m = Matrix()
        for r, c in pixels:
            m.set(r, c, b)
        m.send(dev)
        time.sleep(0.07)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("style", choices=["envelope", "question"])
    parser.add_argument("--duration", type=int, default=2000)
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    pixels = _ENVELOPE if args.style == "envelope" else _QMARK
    _draw(args.dev, pixels, args.duration)
