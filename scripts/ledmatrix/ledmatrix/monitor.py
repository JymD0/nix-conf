import argparse
import time
from ledmatrix import Matrix, ROWS, COLS

# 7 wide x 28 tall rect centered on portrait 9x34 display
_RECT_R = 3   # (34 - 28) // 2
_RECT_C = 1   # (9 - 7) // 2
_RECT_H = 28
_RECT_W = 7


def _rect_pixels(r0, c0, h, w):
    px = []
    for c in range(c0, c0 + w):
        px.append((r0, c))
        px.append((r0 + h - 1, c))
    for r in range(r0 + 1, r0 + h - 1):
        px.append((r, c0))
        px.append((r, c0 + w - 1))
    return px


def _connect(dev):
    cr = _RECT_R + _RECT_H // 2  # row 17
    cc = _RECT_C + _RECT_W // 2  # col 4

    stages = [
        _rect_pixels(cr,      cc,     1,  1),
        _rect_pixels(cr - 2,  cc - 1, 5,  3),
        _rect_pixels(cr - 5,  cc - 2, 11, 5),
        _rect_pixels(cr - 9,  cc - 3, 19, 7),
        _rect_pixels(_RECT_R, _RECT_C, _RECT_H, _RECT_W),
    ]

    for px in stages:
        m = Matrix()
        for r, c in px:
            m.set(r, c, 255)
        m.send(dev)
        time.sleep(0.06)

    m = Matrix()
    for r in range(_RECT_R, _RECT_R + _RECT_H):
        for c in range(_RECT_C, _RECT_C + _RECT_W):
            m.set(r, c, 255)
    m.send(dev)
    time.sleep(0.1)

    for b in [180, 120, 60, 0]:
        m = Matrix()
        for r in range(_RECT_R, _RECT_R + _RECT_H):
            for c in range(_RECT_C, _RECT_C + _RECT_W):
                m.set(r, c, b)
        m.send(dev)
        time.sleep(0.07)


def _disconnect(dev):
    cr = _RECT_R + _RECT_H // 2
    cc = _RECT_C + _RECT_W // 2

    stages = [
        _rect_pixels(_RECT_R, _RECT_C, _RECT_H, _RECT_W),
        _rect_pixels(cr - 9,  cc - 3, 19, 7),
        _rect_pixels(cr - 5,  cc - 2, 11, 5),
        _rect_pixels(cr - 2,  cc - 1, 5,  3),
        _rect_pixels(cr,      cc,     1,  1),
    ]

    for px in stages:
        m = Matrix()
        for r, c in px:
            m.set(r, c, 255)
        m.send(dev)
        time.sleep(0.07)

    Matrix().send(dev)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["connect", "disconnect"])
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()
    if args.action == "connect":
        _connect(args.dev)
    else:
        _disconnect(args.dev)
