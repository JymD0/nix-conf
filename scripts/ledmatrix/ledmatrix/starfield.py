import argparse
import os
import random
import time
from ledmatrix import Matrix, ROWS, COLS

MAX_Z  = 8.0
SCALE  = 3.0
CENTER_R = ROWS // 2
CENTER_C = COLS // 2


def _make_star():
    return {
        "x":     random.uniform(-COLS * SCALE, COLS * SCALE),
        "y":     random.uniform(-ROWS * SCALE, ROWS * SCALE),
        "z":     random.uniform(1.0, MAX_Z),
        "speed": random.uniform(0.05, 0.15),
    }


def _build_starfield_frame(stars):
    m = Matrix()
    for s in stars:
        if s["z"] <= 0:
            continue
        c = round(s["x"] / s["z"] + CENTER_C)
        r = round(s["y"] / s["z"] + CENTER_R)
        if 0 <= r < ROWS and 0 <= c < COLS:
            m.set(r, c, int(255 * (1 - s["z"] / MAX_Z)))
    return m


def _step_stars(stars):
    for s in stars:
        s["z"] -= s["speed"]
        c = round(s["x"] / max(s["z"], 0.01) + CENTER_C)
        r = round(s["y"] / max(s["z"], 0.01) + CENTER_R)
        if s["z"] < 0.5 or not (0 <= r < ROWS and 0 <= c < COLS):
            s.update(_make_star())
            s["z"] = MAX_Z
    return stars


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    pid_file = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ledmatrix-starfield.pid")
    with open(pid_file, "w") as f:
        f.write(str(os.getpid()))

    try:
        stars = [_make_star() for _ in range(30)]
        while True:
            _build_starfield_frame(stars).send(args.dev)
            _step_stars(stars)
            time.sleep(0.04)
    finally:
        try:
            os.unlink(pid_file)
        except OSError:
            pass
