import argparse
import math
import os
import time
from ledmatrix import Matrix, ROWS, COLS, PRIO_IDLE, claim

# A full-width horizontal bar sweeps up and down the display.
# Brightness falls off with a gaussian-ish curve from the bar's center row,
# giving a smooth glow rather than a hard edge.
SPEED = 0.7    # rows per frame
SIGMA = 3.5    # half-width of the glow in rows


def _build_frame(pos):
    m = Matrix()
    for r in range(ROWS):
        dist = abs(r - pos)
        if dist < SIGMA * 3:
            b = int(255 * math.exp(-(dist ** 2) / (2 * SIGMA ** 2)))
            if b > 0:
                for c in range(COLS):
                    m.set(r, c, b)
    return m


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    pid_file = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ledmatrix-scan.pid")
    with open(pid_file, "w") as f:
        f.write(str(os.getpid()))

    pos = 0.0
    direction = 1

    try:
        with claim(PRIO_IDLE) as acquired:
            if not acquired:
                return
            while True:
                _build_frame(pos).send(args.dev)

                pos += direction * SPEED
                if pos >= ROWS - 1:
                    pos = ROWS - 1
                    direction = -1
                elif pos <= 0:
                    pos = 0
                    direction = 1

                time.sleep(0.04)
    finally:
        try:
            os.unlink(pid_file)
        except OSError:
            pass
