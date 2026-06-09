import argparse
import signal
import sys
import time
from ledmatrix import Matrix, ROWS, COLS, PRIO_FEEDBACK, claim

signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

# Exclamation mark: 7-row bar + 1-row gap + 2-row dot, centered vertically.
_EXCL_R = (ROWS - 10) // 2
_EXCL_COLS = [3, 4, 5]   # 3-wide, centered on col 4


def _send(dev, rows, brightness=255):
    m = Matrix()
    for dr in rows:
        for c in _EXCL_COLS:
            m.set(_EXCL_R + dr, c, brightness)
    m.send(dev)


def _ring(dev, duration_ms):
    revealed = set()

    # Dot appears first
    for dr in [8, 9]:
        revealed.add(dr)
    _send(dev, revealed)
    time.sleep(0.08)

    # Bar shoots upward from just above the dot
    for dr in range(6, -1, -1):
        revealed.add(dr)
        _send(dev, revealed)
        time.sleep(0.038)

    # Single flash to punctuate
    _send(dev, revealed, brightness=160)
    time.sleep(0.045)
    _send(dev, revealed, brightness=255)
    time.sleep(0.045)

    # Hold for remaining duration (~0.55s used so far)
    time.sleep(max(0.0, duration_ms / 1000 - 0.55 - 0.36))

    # Smooth fade out
    for b in [210, 160, 110, 60, 20, 0]:
        _send(dev, revealed, brightness=b)
        time.sleep(0.06)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("style", choices=["exclamation", "question", "bell", "envelope"],
                        nargs="?", default="exclamation")
    parser.add_argument("--duration", type=int, default=2000)
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    with claim(PRIO_FEEDBACK) as acquired:
        if not acquired:
            return
        _ring(args.dev, args.duration)
