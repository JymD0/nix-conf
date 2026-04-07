import argparse
import os
import random
import time
from ledmatrix import Matrix, ROWS, COLS

SCALE = 40.0


def _make_blob():
    return {
        "r":      random.uniform(0, ROWS - 1),
        "c":      random.uniform(0, COLS - 1),
        "vr":     random.choice([-1, 1]) * random.uniform(0.05, 0.15),
        "vc":     random.choice([-1, 1]) * random.uniform(0.05, 0.15),
        "radius": random.uniform(6, 10),
    }


def _build_metaballs_frame(blobs):
    m = Matrix()
    for r in range(ROWS):
        for c in range(COLS):
            influence = sum(
                b["radius"] ** 2 / max((r - b["r"]) ** 2 + (c - b["c"]) ** 2, 0.01)
                for b in blobs
            )
            m.set(r, c, min(255, int(influence * SCALE)))
    return m


def _step_blobs(blobs):
    for b in blobs:
        b["r"] += b["vr"]
        b["c"] += b["vc"]
        if b["r"] < 0 or b["r"] >= ROWS:
            b["vr"] *= -1
            b["r"] = max(0.0, min(float(ROWS - 1), b["r"]))
        if b["c"] < 0 or b["c"] >= COLS:
            b["vc"] *= -1
            b["c"] = max(0.0, min(float(COLS - 1), b["c"]))
    return blobs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    pid_file = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ledmatrix-metaballs.pid")
    with open(pid_file, "w") as f:
        f.write(str(os.getpid()))

    try:
        blobs = [_make_blob() for _ in range(3)]
        while True:
            _build_metaballs_frame(blobs).send(args.dev)
            _step_blobs(blobs)
            time.sleep(0.05)
    finally:
        try:
            os.unlink(pid_file)
        except OSError:
            pass
