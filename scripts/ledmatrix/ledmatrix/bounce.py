import argparse
import os
import time
from collections import deque
from ledmatrix import Matrix, ROWS, COLS, PRIO_IDLE, claim

TRAIL = 8
BALLS = [
    {"x": 2.0, "y": 8.0,  "vx":  0.31, "vy":  0.47},
    {"x": 6.0, "y": 22.0, "vx": -0.23, "vy":  0.61},
]


def _step(balls):
    for b in balls:
        b["x"] += b["vx"]
        b["y"] += b["vy"]
        if b["x"] < 0:
            b["x"] = -b["x"]
            b["vx"] = abs(b["vx"])
        elif b["x"] >= COLS:
            b["x"] = 2 * (COLS - 1) - b["x"]
            b["vx"] = -abs(b["vx"])
        if b["y"] < 0:
            b["y"] = -b["y"]
            b["vy"] = abs(b["vy"])
        elif b["y"] >= ROWS:
            b["y"] = 2 * (ROWS - 1) - b["y"]
            b["vy"] = -abs(b["vy"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    pid_file = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ledmatrix-bounce.pid")
    with open(pid_file, "w") as f:
        f.write(str(os.getpid()))

    trails = [deque(maxlen=TRAIL) for _ in BALLS]

    try:
        with claim(PRIO_IDLE) as acquired:
            if not acquired:
                return
            while True:
                _step(BALLS)
                for i, b in enumerate(BALLS):
                    trails[i].append((int(b["x"]), int(b["y"])))

                m = Matrix()
                for trail in trails:
                    for x, y in trail:
                        m.set(y, x, 255)
                m.send(args.dev)
                time.sleep(0.06)
    finally:
        try:
            os.unlink(pid_file)
        except OSError:
            pass
