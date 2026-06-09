import argparse
import time
from ledmatrix import Matrix, ROWS, COLS, PRIO_SYSTEM, claim

# Battery icon: nub (1 row) + body (12 rows), 13 rows tall, 7 wide, centered.
_R = (ROWS - 13) // 2   # = 10
_L = 1                   # leftmost col of body (cols 1-7)
_FILL_B = 190            # lit interior cells


def _battery_pct():
    for path in ["/sys/class/power_supply/BAT1/capacity",
                 "/sys/class/power_supply/BAT0/capacity"]:
        try:
            return max(0, min(100, int(open(path).read().strip())))
        except (OSError, ValueError):
            pass
    return 15


def _build(pct, scale=1.0):
    m = Matrix()
    fill_rows = round(max(0, min(100, pct)) / 100 * 10)

    def px(r, c, base=255):
        m.set(r, c, int(base * scale))

    # Nub (positive terminal, 3 wide, 1 row above body)
    for c in [3, 4, 5]:
        px(_R, c)

    # Body outline
    for c in range(_L, _L + 7):
        px(_R + 1, c)     # top edge
        px(_R + 12, c)    # bottom edge
    for r in range(_R + 2, _R + 12):
        px(r, _L)         # left side
        px(r, _L + 6)     # right side

    # Interior fill: 10 rows (rows _R+2 to _R+11), 5 cols wide
    for i in range(10):
        r = _R + 11 - i   # fill from bottom upward
        if i < fill_rows:
            for c in range(_L + 1, _L + 6):
                px(r, c, _FILL_B)

    return m


def _send(dev, pct, scale=1.0):
    _build(pct, scale).send(dev)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--battery", type=int, default=None)
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    pct = args.battery if args.battery is not None else _battery_pct()

    with claim(PRIO_SYSTEM) as acquired:
        if not acquired:
            return

        # Show battery icon at actual level
        _send(args.dev, pct)
        time.sleep(0.35)

        # Three urgent double-pulses: dim → bright → dim → bright
        for _ in range(3):
            _send(args.dev, pct, scale=0.2)
            time.sleep(0.09)
            _send(args.dev, pct, scale=1.0)
            time.sleep(0.12)
            _send(args.dev, pct, scale=0.2)
            time.sleep(0.09)
            _send(args.dev, pct, scale=1.0)
            time.sleep(0.4)

        # Hold
        time.sleep(0.6)

        # Fade out
        for s in [0.75, 0.5, 0.3, 0.15, 0.05, 0.0]:
            _send(args.dev, pct, scale=s)
            time.sleep(0.055)
