import argparse
import math
import os
import time
from ledmatrix import Matrix, ROWS, COLS


def _build_plasma_frame(t):
    m = Matrix()
    for r in range(ROWS):
        for c in range(COLS):
            v = (
                math.sin(r / 4.0 + t) +
                math.sin(c / 2.0 + t * 0.7) +
                math.sin((r + c) / 5.0 + t * 0.5)
            ) / 3.0
            m.set(r, c, int((v + 1) / 2 * 255))
    return m


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    pid_file = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ledmatrix-plasma.pid")
    with open(pid_file, "w") as f:
        f.write(str(os.getpid()))

    try:
        t = 0.0
        while True:
            _build_plasma_frame(t).send(args.dev)
            t += 0.15
            time.sleep(0.04)
    finally:
        try:
            os.unlink(pid_file)
        except OSError:
            pass
