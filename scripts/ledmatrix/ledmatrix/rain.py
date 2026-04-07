import argparse
import math
import os
import random
import time
from ledmatrix import Matrix, ROWS, COLS


def _make_column():
    return {
        "pos":   random.uniform(-ROWS, 0),
        "speed": random.uniform(0.4, 1.2),
        "trail": random.randint(8, 18),
    }


def _build_rain_frame(columns):
    m = Matrix()
    for c, col in enumerate(columns):
        head = int(col["pos"])
        for offset in range(col["trail"] + 1):
            r = head - offset
            if 0 <= r < ROWS:
                b = 255 if offset == 0 else int(255 * math.exp(-offset * 0.25))
                m.set(r, c, b)
    return m


def _step_columns(columns):
    for col in columns:
        col["pos"] += col["speed"]
        if col["pos"] - col["trail"] >= ROWS:
            col["pos"]   = random.uniform(-ROWS, 0)
            col["speed"] = random.uniform(0.4, 1.2)
            col["trail"] = random.randint(8, 18)
    return columns


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    pid_file = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ledmatrix-rain.pid")
    with open(pid_file, "w") as f:
        f.write(str(os.getpid()))

    try:
        columns = [_make_column() for _ in range(COLS)]
        for col in columns:
            col["pos"] = random.uniform(-ROWS, ROWS)
        while True:
            _build_rain_frame(columns).send(args.dev)
            _step_columns(columns)
            time.sleep(0.04)
    finally:
        try:
            os.unlink(pid_file)
        except OSError:
            pass
