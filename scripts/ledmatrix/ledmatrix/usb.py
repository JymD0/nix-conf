import argparse
import signal
import sys
import time
from ledmatrix import Matrix, ROWS, COLS, PRIO_FEEDBACK, claim

signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

# Female (top): hollow n-shape — top bar solid, 3 hollow side rows, open bottom.
# Male (bottom): narrower solid block (cols 2-6), slides 2 rows into the female hollow.
#
# Connected (cols 0-8):
#   ·███████·   female top bar (cols 1-7)
#   ·█·····█·   female hollow
#   ·███████·   female side (1,7) + male (2-6) — male inside
#   ·███████·   female side (1,7) + male (2-6) — male inside
#   ··█████··   male below female (cols 2-6)
#
# Cable: col 4, dim, from each connector to its screen edge.

_F_COLS = list(range(1, 8))   # cols 1-7
_F_SIDES = [1, 7]
_M_COLS = list(range(2, 7))   # cols 2-6 — one narrower on each side
_CABLE_COL = 4

_F_H = 4    # female: top bar + 3 hollow side rows
_M_H = 3    # male: 2 rows inside female + 1 row below

_CENTER = ROWS // 2   # 17

_F_TOP_END = _CENTER - 2   # 15 — female rows 15-18
_M_TOP_END = _CENTER - 1   # 16 — male rows 16-18, overlaps female rows 16-18

_F_TOP_START = 1
_M_TOP_START = ROWS - _M_H - 1   # 30


def _draw(m, f_top, m_top, brightness=255, cable_b=150):
    for r in range(f_top):
        if 0 <= r < ROWS:
            m.set(r, _CABLE_COL, cable_b)
    # Female top bar
    if 0 <= f_top < ROWS:
        for c in _F_COLS:
            m.set(f_top, c, brightness)
    # Female hollow side rows
    for i in range(1, _F_H):
        r = f_top + i
        if 0 <= r < ROWS:
            for c in _F_SIDES:
                m.set(r, c, brightness)
    # Male solid block (narrower, slides into female)
    for i in range(_M_H):
        r = m_top + i
        if 0 <= r < ROWS:
            for c in _M_COLS:
                m.set(r, c, brightness)
    for r in range(m_top + _M_H, ROWS):
        m.set(r, _CABLE_COL, cable_b)


def _plug(dev):
    STEPS = 10
    for step in range(STEPS + 1):
        t = step / STEPS
        t_e = 1 - (1 - t) ** 2
        f_top = round(_F_TOP_START + (_F_TOP_END - _F_TOP_START) * t_e)
        m_top = round(_M_TOP_START + (_M_TOP_END - _M_TOP_START) * t_e)
        m = Matrix()
        _draw(m, f_top, m_top)
        m.send(dev)
        time.sleep(0.033)

    for b in [145, 255, 145, 255]:
        m = Matrix()
        _draw(m, _F_TOP_END, _M_TOP_END, brightness=b, cable_b=round(b * 0.6))
        m.send(dev)
        time.sleep(0.055)

    m = Matrix()
    _draw(m, _F_TOP_END, _M_TOP_END)
    m.send(dev)
    time.sleep(0.5)

    for b in [200, 140, 80, 30, 0]:
        m = Matrix()
        _draw(m, _F_TOP_END, _M_TOP_END, brightness=b, cable_b=round(b * 0.6))
        m.send(dev)
        time.sleep(0.055)


def _unplug(dev):
    m = Matrix()
    _draw(m, _F_TOP_END, _M_TOP_END)
    m.send(dev)
    time.sleep(0.2)

    for b in [100, 255, 60, 255]:
        m = Matrix()
        _draw(m, _F_TOP_END, _M_TOP_END, brightness=b, cable_b=round(b * 0.6))
        m.send(dev)
        time.sleep(0.055)

    STEPS = 10
    for step in range(STEPS + 1):
        t = (step / STEPS) ** 2
        f_top = round(_F_TOP_END + (_F_TOP_START - _F_TOP_END) * t)
        m_top = round(_M_TOP_END + (_M_TOP_START - _M_TOP_END) * t)
        m = Matrix()
        _draw(m, f_top, m_top)
        m.send(dev)
        time.sleep(0.033)

    Matrix().send(dev)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["plug", "unplug"])
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    with claim(PRIO_FEEDBACK) as acquired:
        if not acquired:
            return
        if args.action == "plug":
            _plug(args.dev)
        else:
            _unplug(args.dev)
