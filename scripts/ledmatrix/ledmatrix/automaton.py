import argparse
import os
import random
import time
from ledmatrix import Matrix, ROWS, COLS, PRIO_IDLE, claim

# Rule 90: new[i] = cells[i-1] XOR cells[i+1] (with wraparound)
# Produces Sierpinski-triangle-like patterns from a single seed.


def _step(cells):
    n = len(cells)
    return [cells[(i - 1) % n] ^ cells[(i + 1) % n] for i in range(n)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    pid_file = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ledmatrix-automaton.pid")
    with open(pid_file, "w") as f:
        f.write(str(os.getpid()))

    try:
        with claim(PRIO_IDLE) as acquired:
            if not acquired:
                return
            cells = [0] * COLS
            cells[COLS // 2] = 1  # single center seed
            gen = 0

            # rolling display buffer: list of ROWS rows (oldest at top)
            display = [[0] * COLS for _ in range(ROWS)]

            while True:
                display = display[1:] + [cells[:]]

                if not any(cells) or gen % (ROWS * 2) == 0:
                    cells = [random.randint(0, 1) for _ in range(COLS)]
                else:
                    cells = _step(cells)
                gen += 1

                m = Matrix()
                for r, row in enumerate(display):
                    for c, v in enumerate(row):
                        m.set(r, c, 255 if v else 0)
                m.send(args.dev)
                time.sleep(0.12)
    finally:
        try:
            os.unlink(pid_file)
        except OSError:
            pass
