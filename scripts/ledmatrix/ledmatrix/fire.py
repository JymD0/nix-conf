import argparse
import os
import random
import time
from ledmatrix import Matrix, ROWS, COLS


def _step_heat(heat):
    for c in range(COLS):
        heat[ROWS - 1][c] = random.uniform(200, 255)
        heat[ROWS - 2][c] = random.uniform(180, 240)
    new = [[0.0] * COLS for _ in range(ROWS)]
    for r in range(ROWS - 2):
        for c in range(COLS):
            left   = heat[r + 1][max(0, c - 1)]
            center = heat[r + 1][c]
            right  = heat[r + 1][min(COLS - 1, c + 1)]
            new[r][c] = max(0.0, (left + center + right) / 3 - random.uniform(4, 8))
    new[ROWS - 2] = heat[ROWS - 2][:]
    new[ROWS - 1] = heat[ROWS - 1][:]
    return new


def _build_fire_frame(heat):
    m = Matrix()
    for r in range(ROWS):
        for c in range(COLS):
            m.set(r, c, int(heat[r][c]))
    return m


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    pid_file = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ledmatrix-fire.pid")
    with open(pid_file, "w") as f:
        f.write(str(os.getpid()))

    try:
        heat = [[0.0] * COLS for _ in range(ROWS)]
        while True:
            heat = _step_heat(heat)
            _build_fire_frame(heat).send(args.dev)
            time.sleep(0.04)
    finally:
        try:
            os.unlink(pid_file)
        except OSError:
            pass
