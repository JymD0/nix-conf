import argparse
import fcntl
import os
import signal
import subprocess
import time
from ledmatrix import Matrix, ROWS, COLS, PRIO_FEEDBACK, claim

_BODY_BRIGHTNESS = 180


def _height(value):
    return round(max(0, min(100, value)) / 100 * ROWS)


def _build_bar(h, lead=255):
    m = Matrix()
    if h <= 0:
        return m
    top = ROWS - h
    for r in range(top + 1, ROWS):
        for c in range(COLS):
            m.set(r, c, _BODY_BRIGHTNESS)
    for c in range(COLS):
        m.set(top, c, lead)
    return m


def _animate(dev, old_val, new_val):
    old_h = _height(old_val)
    new_h = _height(new_val)

    FRAMES = 7
    for step in range(FRAMES + 1):
        t = step / FRAMES
        t_e = 1 - (1 - t) ** 2   # ease out
        h = round(old_h + (new_h - old_h) * t_e)
        _build_bar(h).send(dev)
        if step < FRAMES:
            time.sleep(0.022)

    # Two quick pulses on the leading edge to confirm the new level
    for lead in [155, 255, 155, 255]:
        _build_bar(new_h, lead=lead).send(dev)
        time.sleep(0.04)


def _swap_pid(pid_file):
    """Atomically replace PID file. Returns the old PID or None."""
    with open(pid_file, "a+") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.seek(0)
        old = f.read().strip()
        f.seek(0)
        f.truncate()
        f.write(str(os.getpid()))
    try:
        return int(old)
    except ValueError:
        return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("value", type=int, nargs="?", default=None)
    parser.add_argument("--prev", type=int, default=None)
    parser.add_argument("--clear", action="store_true")
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    pid_file = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ledmatrix-bar.pid")
    state_file = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ledmatrix-bar-state")

    if args.clear:
        try:
            cur_val = int(open(state_file).read().strip())
        except (OSError, ValueError):
            cur_val = 0
        try:
            os.unlink(state_file)
        except OSError:
            pass
        if cur_val > 0:
            with claim(PRIO_FEEDBACK) as acquired:
                if acquired:
                    cur_h = _height(cur_val)
                    FRAMES = 6
                    for step in range(FRAMES + 1):
                        t = (step / FRAMES) ** 2   # ease in, gravity-like drop
                        h = round(cur_h * (1 - t))
                        _build_bar(h).send(args.dev)
                        if step < FRAMES:
                            time.sleep(0.025)
                    Matrix().send(args.dev)
        else:
            Matrix().send(args.dev)
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

    # Serialise concurrent bar instances: kill any already-running one so only
    # the most recent invocation animates. The flock makes the read-write atomic.
    old_pid = _swap_pid(pid_file)
    if old_pid and old_pid != os.getpid():
        try:
            os.kill(old_pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        time.sleep(0.05)

    try:
        with claim(PRIO_FEEDBACK) as acquired:
            if not acquired:
                return
            _animate(args.dev, prev, value)
    finally:
        try:
            with open(pid_file, "a+") as f:
                fcntl.flock(f, fcntl.LOCK_EX)
                f.seek(0)
                if f.read().strip() == str(os.getpid()):
                    f.seek(0)
                    f.truncate()
        except OSError:
            pass

    # Reset the clear timer. Stop any existing one first so the new 3s window
    # starts from the most recent change, not the first.
    subprocess.run(
        ["systemctl", "--user", "stop", "ledmatrix-bar-clear.timer"],
        capture_output=True,
    )
    subprocess.run(
        ["systemd-run", "--user", "--on-active=3s",
         "--timer-property=AccuracySec=500ms",
         "--unit=ledmatrix-bar-clear",
         "ledmatrix-bar", "--clear"],
        capture_output=True,
    )
