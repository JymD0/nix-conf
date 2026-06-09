import argparse
import os
import random
import time
from ledmatrix import Matrix, ROWS, COLS, PRIO_IDLE, claim

# Each column has a single drop falling at its own speed, with a fading trail.
# Speeds are intentionally uneven so columns desynchronise naturally.
SPEEDS = [0.20, 0.27, 0.35, 0.41, 0.50, 0.31, 0.44, 0.24, 0.38]
TRAIL = 8


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    pid_file = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ledmatrix-cascade.pid")
    with open(pid_file, "w") as f:
        f.write(str(os.getpid()))

    pos = [random.uniform(0, ROWS) for _ in range(COLS)]

    try:
        with claim(PRIO_IDLE) as acquired:
            if not acquired:
                return
            while True:
                m = Matrix()
                for c in range(COLS):
                    pos[c] = (pos[c] + SPEEDS[c]) % ROWS
                    head = int(pos[c])
                    m.set(head, c, 255)
                    for i in range(1, TRAIL + 1):
                        r = (head - i) % ROWS
                        b = int(220 * (1 - i / TRAIL) ** 1.8)
                        if b > m.get(r, c):
                            m.set(r, c, b)
                m.send(args.dev)
                time.sleep(0.06)
    finally:
        try:
            os.unlink(pid_file)
        except OSError:
            pass
