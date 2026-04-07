import argparse
import time
from ledmatrix import Matrix

# 5 wide x 15 tall bolt, centered on portrait 9x34 display
# _BOLT_R = (34-15)//2 = 9, _BOLT_C = (9-5)//2 = 2
_BOLT = [
    (0,  2), (0,  3),
    (1,  2), (1,  3),
    (2,  1), (2,  2), (2,  3),
    (3,  1), (3,  2), (3,  3),
    (4,  0), (4,  1), (4,  2), (4,  3), (4,  4),
    (5,  0), (5,  1), (5,  2), (5,  3), (5,  4),
    (6,  2), (6,  3), (6,  4),
    (7,  2), (7,  3), (7,  4),
    (8,  3), (8,  4),
    (9,  3), (9,  4),
    (10, 3),
    (11, 3),
    (12, 3),
    (13, 3),
    (14, 3),
]
_BOLT_R = 9
_BOLT_C = 2


def _draw_bolt(m, brightness):
    for dr, dc in _BOLT:
        m.set(_BOLT_R + dr, _BOLT_C + dc, brightness)


def _plug(dev):
    m = Matrix()
    _draw_bolt(m, 255)
    m.send(dev)
    time.sleep(0.05)

    for b in [230, 210, 190, 180]:
        m = Matrix()
        _draw_bolt(m, b)
        m.send(dev)
        time.sleep(0.04)

    for b in [200, 230, 255]:
        m = Matrix()
        _draw_bolt(m, b)
        m.send(dev)
        time.sleep(0.04)

    time.sleep(1.0)

    for b in [200, 150, 100, 50, 0]:
        m = Matrix()
        _draw_bolt(m, b)
        m.send(dev)
        time.sleep(0.05)


def _unplug(dev):
    m = Matrix()
    _draw_bolt(m, 255)
    m.send(dev)
    time.sleep(0.1)

    bolt_by_col = {}
    for dr, dc in _BOLT:
        bolt_by_col.setdefault(dc, []).append(dr)

    for dc in range(4, -1, -1):
        rows = sorted(bolt_by_col.get(dc, []), reverse=True)
        for dr in rows:
            m = Matrix()
            remaining = [
                (r, c) for (r, c) in _BOLT
                if not (c == dc and r >= dr) and not (c > dc)
            ]
            for r2, c2 in remaining:
                m.set(_BOLT_R + r2, _BOLT_C + c2, 255)
            m.send(dev)
            time.sleep(0.015)
        time.sleep(0.04)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["plug", "unplug"])
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()
    if args.action == "plug":
        _plug(args.dev)
    else:
        _unplug(args.dev)
