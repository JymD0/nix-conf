import argparse
import os
import subprocess
import time
from ledmatrix import Matrix, ROWS, COLS


def n_lit_for(value):
    return round(value / 100 * ROWS * COLS)


def build_frame(value):
    m = Matrix()
    n = n_lit_for(max(0, min(100, value)))
    for i in range(n):
        m.set(*m.snake_pos(i), 255)
    return m


def _animate(dev, n_old, n_new):
    FRAME_MS = 0.03
    STEPS = 4

    if n_new >= n_old:
        new_indices = list(range(n_old, n_new))
        for step in range(STEPS + 1):
            m = Matrix()
            for i in range(n_old):
                m.set(*m.snake_pos(i), 255)
            for i in new_indices:
                final_row, col = m.snake_pos(i)
                anim_row = int(final_row * step / STEPS)
                m.set(anim_row, col, 255)
            m.send(dev)
            if step < STEPS:
                time.sleep(FRAME_MS)
    else:
        removed = list(range(n_new, n_old))
        for step in range(STEPS + 1):
            m = Matrix()
            for i in range(n_new):
                m.set(*m.snake_pos(i), 255)
            for i in removed:
                final_row, col = m.snake_pos(i)
                anim_row = int(final_row * (1 - step / STEPS))
                if anim_row >= 0:
                    m.set(anim_row, col, 255)
            m.send(dev)
            if step < STEPS:
                time.sleep(FRAME_MS)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("value", type=int, nargs="?", default=None)
    parser.add_argument("--prev", type=int, default=None)
    parser.add_argument("--clear", action="store_true")
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    state_file = os.path.join(
        os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ledmatrix-bar-state"
    )

    if args.clear:
        Matrix().send(args.dev)
        try:
            os.unlink(state_file)
        except OSError:
            pass
        return

    if args.value is None:
        return

    value = max(0, min(100, args.value))

    if args.prev is not None:
        prev = args.prev
    else:
        try:
            prev = int(open(state_file).read().strip())
        except (OSError, ValueError):
            prev = 0

    with open(state_file, "w") as f:
        f.write(str(value))

    _animate(args.dev, n_lit_for(prev), n_lit_for(value))

    subprocess.run(
        ["systemd-run", "--user", "--on-active=3s",
         "--timer-property=AccuracySec=500ms",
         "--unit=ledmatrix-bar-clear",
         "ledmatrix-bar", "--clear"],
        capture_output=True,
    )
