import os
import struct
import subprocess
import tempfile
import zlib

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

        raw = b""
        for r in range(ROWS):
            raw += b"\x00"
            for c in range(COLS):
                raw += bytes([self.buf[r][c]])

        png = b"\x89PNG\r\n\x1a\n"
        png += _png_chunk(b"IHDR", struct.pack(">IIBBBBB", COLS, ROWS, 8, 0, 0, 0, 0))
        png += _png_chunk(b"IDAT", zlib.compress(raw))
        png += _png_chunk(b"IEND", b"")

        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            f.write(png)
            tmp = f.name
        try:
            subprocess.run(
                [tool, "--serial-dev", dev, "led-matrix", "--image-gray", tmp],
                check=False,
                capture_output=True,
            )
        finally:
            os.unlink(tmp)
