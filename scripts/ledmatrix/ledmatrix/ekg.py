import argparse
import math
import os
import time
from ledmatrix import Matrix, ROWS, COLS, PRIO_IDLE, claim

CENTER = ROWS // 2
AMPLITUDE = ROWS // 2 - 2  # 15 rows


def _heartbeat_row(t):
    """Return row position (0=top) for a heartbeat trace at time t."""
    period = 1.5
    phase = (t % period) / period
    if phase < 0.3:
        v = 0.0
    elif phase < 0.35:
        v = -(phase - 0.3) / 0.05        # 0 to -1 (spike up)
    elif phase < 0.45:
        v = -1.0 + 2.0 * (phase - 0.35) / 0.10  # -1 to 1 (drop down)
    elif phase < 0.55:
        v = 1.0 - (phase - 0.45) / 0.10  # 1 to 0 (return)
    else:
        v = 0.0
    return max(0, min(ROWS - 1, CENTER + int(v * AMPLITUDE)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    pid_file = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ledmatrix-ekg.pid")
    with open(pid_file, "w") as f:
        f.write(str(os.getpid()))

    try:
        with claim(PRIO_IDLE) as acquired:
            if not acquired:
                return
            history = [CENTER] * COLS
            t = 0.0
            dt = 0.04
            while True:
                history = history[1:] + [_heartbeat_row(t)]
                m = Matrix()
                for col, row in enumerate(history):
                    m.set(row, col, 255)
                m.send(args.dev)
                t += dt
                time.sleep(dt)
    finally:
        try:
            os.unlink(pid_file)
        except OSError:
            pass
