import argparse
import os
import time
from ledmatrix import Matrix, ROWS, COLS, PRIO_IDLE, claim

PIXELS_PER_FRAME = 4
HOLD_FRAMES = 16  # pause when fully filled or fully cleared


def _spiral_path(rows, cols):
    """Generate pixel coordinates tracing a rectangle spiral from outside in."""
    path = []
    top, bottom, left, right = 0, rows - 1, 0, cols - 1
    while top <= bottom and left <= right:
        for c in range(left, right + 1):
            path.append((top, c))
        top += 1
        for r in range(top, bottom + 1):
            path.append((r, right))
        right -= 1
        if top <= bottom:
            for c in range(right, left - 1, -1):
                path.append((bottom, c))
            bottom -= 1
        if left <= right:
            for r in range(bottom, top - 1, -1):
                path.append((r, left))
            left += 1
    return path


PATH = _spiral_path(ROWS, COLS)
TOTAL = len(PATH)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    pid_file = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ledmatrix-spiral.pid")
    with open(pid_file, "w") as f:
        f.write(str(os.getpid()))

    try:
        with claim(PRIO_IDLE) as acquired:
            if not acquired:
                return
            lit = set()
            front = 0
            filling = True
            hold = 0

            while True:
                if hold > 0:
                    hold -= 1
                elif filling:
                    for _ in range(PIXELS_PER_FRAME):
                        if front < TOTAL:
                            lit.add(PATH[front])
                            front += 1
                    if front >= TOTAL:
                        hold = HOLD_FRAMES
                        filling = False
                else:
                    for _ in range(PIXELS_PER_FRAME):
                        if front > 0:
                            front -= 1
                            lit.discard(PATH[front])
                    if front <= 0:
                        hold = HOLD_FRAMES // 2
                        filling = True

                m = Matrix()
                for r, c in lit:
                    m.set(r, c, 255)
                m.send(args.dev)
                time.sleep(0.05)
    finally:
        try:
            os.unlink(pid_file)
        except OSError:
            pass
