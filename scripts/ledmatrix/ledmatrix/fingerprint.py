import argparse
import math
import signal
import sys
import time
from ledmatrix import Matrix, ROWS, COLS, PRIO_SYSTEM, claim

signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

_SIGMA = 1.4

# Fingerprint ridges: (row, col_start, col_end_exclusive).
# Narrow at the extremes, full-width at center — approximates the oval of a fingerprint.
_RIDGES = [
    (1,  3, 6),
    (4,  2, 7),
    (7,  1, 8),
    (10, 0, 9),
    (13, 0, 9),
    (16, 0, 9),
    (19, 0, 9),
    (22, 0, 9),
    (25, 1, 8),
    (28, 2, 7),
    (31, 3, 6),
]

_ABORT_ROW = ROWS // 2


def _ridge_frame(revealed, brightness=255):
    m = Matrix()
    for r, cs, ce in revealed:
        for c in range(cs, ce):
            m.set(r, c, brightness)
    return m


def _scan_frame(pos, revealed):
    """Scan stripe overlaid on any already-revealed ridges."""
    m = _ridge_frame(revealed)
    for r in range(ROWS):
        b = int(255 * math.exp(-((r - pos) ** 2) / (2 * _SIGMA ** 2)))
        if b > 2:
            for c in range(COLS):
                m.set(r, c, max(m.get(r, c), b))
    return m


def _sweep(dev, stop_row, step_ms=0.013):
    """Sweep scan line from top to stop_row, revealing ridges as it passes."""
    revealed = []
    ridge_idx = 0
    for pos in range(-3, stop_row):
        while ridge_idx < len(_RIDGES) and _RIDGES[ridge_idx][0] <= pos:
            revealed.append(_RIDGES[ridge_idx])
            ridge_idx += 1
        _scan_frame(pos, revealed).send(dev)
        time.sleep(step_ms)
    return revealed


def _success(dev):
    revealed = _sweep(dev, ROWS + 3)

    # Double pulse over the completed fingerprint
    for b in [145, 255, 145, 255]:
        _ridge_frame(revealed, brightness=b).send(dev)
        time.sleep(0.06)

    _ridge_frame(revealed).send(dev)
    time.sleep(0.4)

    for b in [200, 140, 80, 30, 0]:
        _ridge_frame(revealed, brightness=b).send(dev)
        time.sleep(0.055)


def _failure(dev):
    revealed = _sweep(dev, _ABORT_ROW)

    # Scan stutters — rapid back-and-forth jitter
    for pos in [_ABORT_ROW + 3, _ABORT_ROW - 5, _ABORT_ROW + 2, _ABORT_ROW - 3, _ABORT_ROW]:
        _scan_frame(pos, revealed).send(dev)
        time.sleep(0.055)

    # Two hard strobes then wipe
    for _ in range(2):
        m = Matrix()
        m.fill(255)
        m.send(dev)
        time.sleep(0.055)
        Matrix().send(dev)
        time.sleep(0.05)

    # Wipe remaining ridges top-to-bottom
    for r, cs, ce in list(revealed):
        revealed.remove((r, cs, ce))
        _ridge_frame(revealed).send(dev)
        time.sleep(0.04)

    Matrix().send(dev)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("result", choices=["success", "failure", "scan"],
                        nargs="?", default="scan")
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    with claim(PRIO_SYSTEM) as acquired:
        if not acquired:
            return
        if args.result == "success":
            _success(args.dev)
        elif args.result == "failure":
            _failure(args.dev)
        else:
            _sweep(args.dev, ROWS + 3)
            Matrix().send(args.dev)
