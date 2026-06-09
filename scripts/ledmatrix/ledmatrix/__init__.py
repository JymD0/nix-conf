import contextlib
import fcntl
import math
import os
import signal
import struct
import subprocess
import tempfile
import time
import zlib

PRIO_SYSTEM   = 1  # charging, monitor, network
PRIO_FEEDBACK = 2  # volume bar, notifications
PRIO_IDLE     = 3  # rain, ekg, automaton, bounce, cascade, spiral

_ACTIVE_FILE = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"),
    "ledmatrix-active",
)


def _read_active():
    try:
        parts = open(_ACTIVE_FILE).read().split()
        prio, pid = int(parts[0]), int(parts[1])
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            os.unlink(_ACTIVE_FILE)
            return None, None
        return prio, pid
    except (OSError, ValueError, IndexError):
        return None, None


@contextlib.contextmanager
def claim(priority):
    """Claim the display at a given priority level.

    Yields True if the caller should run, False if a higher-priority effect
    is already active and the caller should skip.
    """
    active_prio, active_pid = _read_active()

    if active_prio is not None and active_prio < priority:
        yield False
        return

    if active_pid is not None:
        try:
            os.kill(active_pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        time.sleep(0.1)

    with open(_ACTIVE_FILE, "w") as f:
        f.write(f"{priority} {os.getpid()}")

    try:
        yield True
    finally:
        _, pid = _read_active()
        if pid == os.getpid():
            try:
                os.unlink(_ACTIVE_FILE)
            except OSError:
                pass


# 4x4 Bayer ordered dithering matrix (values 0-15)
_BAYER = [
    [ 0,  8,  2, 10],
    [12,  4, 14,  6],
    [ 3, 11,  1,  9],
    [15,  7, 13,  5],
]

ROWS = 34  # height of display (34 tall)
COLS = 9   # width of display (9 wide)


class Matrix:
    def __init__(self):
        self.buf = [[0] * COLS for _ in range(ROWS)]

    def clear(self):
        for r in range(ROWS):
            for c in range(COLS):
                self.buf[r][c] = 0

    def fill(self, brightness=255):
        for r in range(ROWS):
            for c in range(COLS):
                self.buf[r][c] = brightness

    def set(self, row, col, brightness):
        if 0 <= row < ROWS and 0 <= col < COLS:
            self.buf[row][col] = max(0, min(255, int(brightness)))

    def get(self, row, col):
        return self.buf[row][col]

    def snake_pos(self, index):
        row = index // COLS
        col = index % COLS
        if row % 2 == 1:
            col = COLS - 1 - col
        return row, col

    def send(self, dev="/dev/ttyACM0", tool="inputmodule-control"):
        if not os.path.exists(dev):
            return

        def _png_chunk(tag, data):
            crc = zlib.crc32(tag + data) & 0xFFFFFFFF
            return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

        # firmware 0.2.0 doesn't support --image-gray; use 1-bit PNG with
        # Bayer ordered dithering so gradients appear as structured dot patterns
        row_bytes = math.ceil(COLS / 8)
        raw = b""
        for r in range(ROWS):
            raw += b"\x00"  # filter byte
            packed = 0
            for c in range(COLS):
                threshold = (_BAYER[r % 4][c % 4] + 0.5) * 255 / 16
                bit = 1 if self.buf[r][c] > threshold else 0
                packed = (packed << 1) | bit
            packed <<= (row_bytes * 8 - COLS)
            raw += packed.to_bytes(row_bytes, "big")

        png = b"\x89PNG\r\n\x1a\n"
        png += _png_chunk(b"IHDR", struct.pack(">IIBBBBB", COLS, ROWS, 1, 0, 0, 0, 0))
        png += _png_chunk(b"IDAT", zlib.compress(raw))
        png += _png_chunk(b"IEND", b"")

        lock_path = f"/run/user/{os.getuid()}/ledmatrix.lock"
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            f.write(png)
            tmp = f.name
        try:
            with open(lock_path, "w") as lf:
                fcntl.flock(lf, fcntl.LOCK_EX)
                try:
                    subprocess.run(
                        [tool, "--serial-dev", dev, "led-matrix", "--image-bw", tmp],
                        check=False,
                        capture_output=True,
                        timeout=3,
                    )
                except subprocess.TimeoutExpired:
                    pass
        finally:
            os.unlink(tmp)
