import argparse
import time
from ledmatrix import Matrix, ROWS, COLS, PRIO_SYSTEM, claim

# Padlock icon, 13 rows tall, centered.
# Shackle: 3 rows (arc top + 2 leg rows), 5 wide (cols 2-6).
# Body: 10 rows (top edge, 8 interior, bottom edge), 7 wide (cols 1-7).
# Locked: shackle sits flush on body top. Open: shackle raised 3 rows.
_LOCK_R = (ROWS - 13) // 2   # = 10; shackle top row when locked


def _build_lock(shackle_lift=0, brightness=255):
    m = Matrix()
    sr = _LOCK_R - shackle_lift   # shackle top row

    def px(r, c):
        m.set(r, c, brightness)

    # Shackle arc
    for c in [3, 4, 5]:
        px(sr, c)              # arc top
    px(sr + 1, 2); px(sr + 1, 6)   # left/right legs
    px(sr + 2, 2); px(sr + 2, 6)

    # Body (always fixed regardless of lift)
    br = _LOCK_R + 3
    for c in range(1, 8):
        px(br, c)              # top edge
        px(br + 9, c)          # bottom edge
    for dr in range(1, 9):
        px(br + dr, 1)         # left side
        px(br + dr, 7)         # right side

    # Keyhole: small circle + stem
    for c in [3, 4, 5]:
        px(br + 2, c)          # circle row 1
        px(br + 3, c)          # circle row 2
    px(br + 5, 4)              # stem

    return m


def _fade_lock(dev, shackle_lift=0):
    for s in [0.75, 0.5, 0.28, 0.12, 0.0]:
        m = _build_lock(shackle_lift, brightness=int(255 * s))
        m.send(dev)
        time.sleep(0.055)


def _do_unlock(dev):
    # Start locked
    _build_lock(0).send(dev)
    time.sleep(0.15)

    # Keyhole flash to signal "reading"
    for b in [80, 255, 80, 255]:
        _build_lock(0, brightness=b).send(dev)
        time.sleep(0.05)

    # Shackle rises in 3 steps
    for lift in range(1, 4):
        _build_lock(lift).send(dev)
        time.sleep(0.08)

    # Hold open briefly
    time.sleep(0.6)
    _fade_lock(dev, shackle_lift=3)


def _do_lock(dev):
    # Start open
    _build_lock(3).send(dev)
    time.sleep(0.2)

    # Shackle drops in 3 steps
    for lift in range(2, -1, -1):
        _build_lock(lift).send(dev)
        time.sleep(0.08)

    # Body click: single bright flash to confirm locked
    _build_lock(0, brightness=255).send(dev)
    time.sleep(0.06)
    _build_lock(0, brightness=140).send(dev)
    time.sleep(0.06)
    _build_lock(0, brightness=255).send(dev)
    time.sleep(0.5)

    _fade_lock(dev, shackle_lift=0)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["lock", "unlock"])
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    with claim(PRIO_SYSTEM) as acquired:
        if not acquired:
            return
        if args.action == "unlock":
            _do_unlock(args.dev)
        else:
            _do_lock(args.dev)
