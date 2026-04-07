# LED Matrix Animations — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `ledmatrix` Python package with a `Matrix` class and 5 event-driven animations, package it via Nix, and wire each animation to its trigger.

**Architecture:** A `buildPythonPackage` derivation in `modules/packages.nix` sources `scripts/ledmatrix/`. Each animation is a CLI entry point that imports `Matrix`, manipulates a 9×34 brightness grid, and streams raw serial frames to `/dev/ttyACM0`. Triggers use systemd user services, udev rules, and existing shell hook integration points.

**Tech Stack:** Python 3, pyserial, Nix `buildPythonPackage`, systemd user services, udev, Hyprland IPC socket, NetworkManager dispatcher, swaync scripts

---

## File structure

| File | Action | Responsibility |
|------|--------|----------------|
| `scripts/ledmatrix/pyproject.toml` | Create | Package metadata and CLI entry points |
| `scripts/ledmatrix/ledmatrix/__init__.py` | Create | `Matrix` class + `send()` |
| `scripts/ledmatrix/ledmatrix/bar.py` | Create | Snake bar animation (volume, brightness) |
| `scripts/ledmatrix/ledmatrix/charging.py` | Create | Lightning bolt (plug/unplug) |
| `scripts/ledmatrix/ledmatrix/monitor.py` | Create | Rectangle expand/contract (monitor connect/disconnect) |
| `scripts/ledmatrix/ledmatrix/network.py` | Create | Arc ping (wifi/tailscale up/down) |
| `scripts/ledmatrix/ledmatrix/notify.py` | Create | Envelope / question mark |
| `scripts/ledmatrix/tests/test_matrix.py` | Create | Unit tests for `Matrix` class |
| `scripts/ledmatrix/tests/test_bar.py` | Create | Unit tests for bar frame generation |
| `modules/packages.nix` | Modify | Add `ledmatrix-pkg` derivation + to `home.packages` |
| `modules/services.nix` | Modify | Add volume watcher, tailscale poller, monitor IPC listener |
| `modules/waybar.nix` | Modify | Append `ledmatrix-bar` call to `brightnessScript` |
| `configuration.nix` | Modify | Add NM dispatcher script for wifi trigger |
| `modules/desktop.nix` | Modify | Add swaync script for notify trigger |

---

### Task 0: Verify the serial FRAME_CMD byte

**Files:** None (manual investigation only)

The `send()` method writes `[0x32, 0xAC, FRAME_CMD] + 306 brightness bytes`. The correct `FRAME_CMD` for a full greyscale frame must be confirmed before implementing `send()`.

- [ ] **Step 1: Install pyserial in a temporary shell**

Run: `nix-shell -p python3Packages.pyserial --run bash`

- [ ] **Step 2: Test candidate byte 0x07**

Run inside that shell:

```python
python3 -c "
import serial
with serial.Serial('/dev/ttyACM0', 115200, timeout=1) as s:
    frame = bytearray(306)
    frame[0] = 255
    s.write(bytes([0x32, 0xAC, 0x07]) + bytes(frame))
print('sent 0x07')
"
```

Expected: the top-left LED lights up, all others dark.
If nothing happens, repeat with `0x06`, then `0x0E`.

- [ ] **Step 3: Test clear (all off)**

```python
python3 -c "
import serial
with serial.Serial('/dev/ttyACM0', 115200, timeout=1) as s:
    s.write(bytes([0x32, 0xAC, 0x07]) + bytes(306))
"
```

Expected: all LEDs off.

- [ ] **Step 4: Note the confirmed byte**

Write the confirmed value as a comment at the top of `scripts/ledmatrix/ledmatrix/__init__.py` when creating it in Task 1. Use it as `_FRAME_CMD`.

---

### Task 1: Package scaffold + Matrix class + tests

**Files:**
- Create: `scripts/ledmatrix/pyproject.toml`
- Create: `scripts/ledmatrix/ledmatrix/__init__.py`
- Create: `scripts/ledmatrix/tests/__init__.py`
- Create: `scripts/ledmatrix/tests/test_matrix.py`

- [ ] **Step 1: Write `tests/test_matrix.py` (failing)**

```python
import pytest
from ledmatrix import Matrix, ROWS, COLS

def test_dimensions():
    m = Matrix()
    assert len(m.buf) == ROWS
    assert len(m.buf[0]) == COLS

def test_set_clamps():
    m = Matrix()
    m.set(0, 0, 300)
    assert m.get(0, 0) == 255
    m.set(0, 0, -10)
    assert m.get(0, 0) == 0

def test_clear():
    m = Matrix()
    m.set(0, 0, 200)
    m.clear()
    assert m.get(0, 0) == 0

def test_fill():
    m = Matrix()
    m.fill(128)
    assert m.get(4, 17) == 128

def test_snake_pos_row0_left_to_right():
    m = Matrix()
    assert m.snake_pos(0) == (0, 0)
    assert m.snake_pos(33) == (0, 33)

def test_snake_pos_row1_right_to_left():
    m = Matrix()
    assert m.snake_pos(34) == (1, 33)
    assert m.snake_pos(67) == (1, 0)

def test_snake_pos_row2_left_to_right():
    m = Matrix()
    assert m.snake_pos(68) == (2, 0)

def test_snake_pos_covers_all_pixels():
    m = Matrix()
    positions = {m.snake_pos(i) for i in range(ROWS * COLS)}
    assert len(positions) == ROWS * COLS
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts/ledmatrix && python3 -m pytest tests/test_matrix.py -v 2>&1 | head -20`

Expected: `ModuleNotFoundError: No module named 'ledmatrix'`

- [ ] **Step 3: Create `scripts/ledmatrix/ledmatrix/__init__.py`**

Replace `_FRAME_CMD = 0x07` with the value confirmed in Task 0.

```python
import os
import serial

ROWS = 9
COLS = 34

# Confirmed in Task 0: command byte for full greyscale frame blit
_FRAME_CMD = 0x07

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

    def send(self, dev="/dev/ttyACM0"):
        if not os.path.exists(dev):
            return
        frame = bytes(self.buf[r][c] for r in range(ROWS) for c in range(COLS))
        with serial.Serial(dev, 115200, timeout=1) as s:
            s.write(bytes([0x32, 0xAC, _FRAME_CMD]) + frame)
```

- [ ] **Step 4: Create `scripts/ledmatrix/tests/__init__.py` — empty init for tests package**

Create `scripts/ledmatrix/tests/__init__.py` as an empty file.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd scripts/ledmatrix && python3 -m pytest tests/test_matrix.py -v`

Expected: all 8 tests pass.

- [ ] **Step 6: Create `scripts/ledmatrix/pyproject.toml`**

```toml
[build-system]
requires = ["setuptools"]
build-backend = "setuptools.build_meta"

[project]
name = "ledmatrix"
version = "0.1.0"
dependencies = ["pyserial"]

[project.scripts]
ledmatrix-bar      = "ledmatrix.bar:main"
ledmatrix-charging = "ledmatrix.charging:main"
ledmatrix-monitor  = "ledmatrix.monitor:main"
ledmatrix-network  = "ledmatrix.network:main"
ledmatrix-notify   = "ledmatrix.notify:main"
```

- [ ] **Step 7: Commit**

```bash
git add scripts/ledmatrix/
git commit -m "feat: add ledmatrix Python package scaffold and Matrix class"
```

---

### Task 2: bar animation + tests

**Files:**
- Create: `scripts/ledmatrix/ledmatrix/bar.py`
- Create: `scripts/ledmatrix/tests/test_bar.py`

- [ ] **Step 1: Write `tests/test_bar.py` (failing)**

```python
from ledmatrix import Matrix
from ledmatrix.bar import build_frame, n_lit_for

def test_n_lit_zero():
    assert n_lit_for(0) == 0

def test_n_lit_hundred():
    assert n_lit_for(100) == 306

def test_n_lit_fifty():
    assert n_lit_for(50) == 153

def test_build_frame_sets_lit_pixels():
    m = build_frame(50)
    assert m.get(0, 0) == 255   # snake index 0
    assert m.get(0, 33) == 255  # snake index 33 (last of row 0)
    assert m.get(1, 33) == 255  # snake index 34 (first of row 1, right-to-left)

def test_build_frame_leaves_unlit_dark():
    m = build_frame(0)
    assert m.get(0, 0) == 0
    assert m.get(4, 17) == 0

def test_build_frame_full():
    m = build_frame(100)
    assert m.get(8, 0) == 255  # last row, last pixel in snake order
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts/ledmatrix && python3 -m pytest tests/test_bar.py -v 2>&1 | head -10`

Expected: `ModuleNotFoundError: No module named 'ledmatrix.bar'`

- [ ] **Step 3: Create `scripts/ledmatrix/ledmatrix/bar.py`**

```python
import argparse
import math
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
        m = Matrix()
        m.send(args.dev)
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

    n_new = n_lit_for(value)
    n_old = n_lit_for(prev)

    _animate(args.dev, n_old, n_new)

    # Reset 3-second auto-clear timer
    subprocess.run(
        [
            "systemd-run", "--user", "--on-active=3s",
            "--timer-property=AccuracySec=500ms",
            "--unit=ledmatrix-bar-clear",
            "ledmatrix-bar", "--clear",
        ],
        capture_output=True,
    )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd scripts/ledmatrix && python3 -m pytest tests/test_bar.py -v`

Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/ledmatrix/ledmatrix/bar.py scripts/ledmatrix/tests/test_bar.py
git commit -m "feat: add ledmatrix bar animation"
```

---

### Task 3: charging animation

**Files:**
- Create: `scripts/ledmatrix/ledmatrix/charging.py`

The bolt sprite is 5 cols × 7 rows, placed at row offset 1, col offset 15 (centered on 34×9 grid).

- [ ] **Step 1: Create `scripts/ledmatrix/ledmatrix/charging.py`**

```python
import argparse
import time
from ledmatrix import Matrix

# Bolt pixel offsets (row, col) relative to BOLT_R, BOLT_C
_BOLT = [
    (0, 2), (0, 3),
    (1, 1), (1, 2),
    (2, 0), (2, 1),
    (3, 0), (3, 1), (3, 2), (3, 3), (3, 4),
    (4, 3), (4, 4),
    (5, 2), (5, 3),
    (6, 1), (6, 2),
]
_BOLT_R = 1   # top-left row of sprite on the 9-row grid
_BOLT_C = 15  # top-left col of sprite on the 34-col grid

def _draw_bolt(m, brightness):
    for dr, dc in _BOLT:
        m.set(_BOLT_R + dr, _BOLT_C + dc, brightness)

def _plug(dev):
    # Flash in
    m = Matrix()
    _draw_bolt(m, 255)
    m.send(dev)
    time.sleep(0.05)

    # Dim to 180
    for b in [230, 210, 190, 180]:
        m = Matrix()
        _draw_bolt(m, b)
        m.send(dev)
        time.sleep(0.04)

    # Pulse back to 255
    for b in [200, 230, 255]:
        m = Matrix()
        _draw_bolt(m, b)
        m.send(dev)
        time.sleep(0.04)

    # Hold 1s
    time.sleep(1.0)

    # Fade out
    for b in [200, 150, 100, 50, 0]:
        m = Matrix()
        _draw_bolt(m, b)
        m.send(dev)
        time.sleep(0.05)

def _unplug(dev):
    m = Matrix()
    _draw_bolt(m, 255)
    m.send(dev)
    time.sleep(0.1)

    # Column wipe bottom-to-top, staggered by sprite column (4 -> 0)
    bolt_by_col = {}
    for dr, dc in _BOLT:
        bolt_by_col.setdefault(dc, []).append(dr)

    for dc in range(4, -1, -1):
        rows = sorted(bolt_by_col.get(dc, []), reverse=True)
        for dr in rows:
            m = Matrix()
            remaining = [
                (r, c) for (r, c) in _BOLT
                if not (c == dc and r >= dr)
                and not (c > dc)
            ]
            for r2, c2 in remaining:
                m.set(_BOLT_R + r2, _BOLT_C + c2, 255)
            m.send(dev)
            time.sleep(0.015)
        time.sleep(0.04)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["plug", "unplug"])
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()
    if args.action == "plug":
        _plug(args.dev)
    else:
        _unplug(args.dev)
```

- [ ] **Step 2: Smoke-test plug animation manually**

Run: `cd scripts/ledmatrix && pip install -e . -q && ledmatrix-charging plug`

Expected: lightning bolt flashes in, dims, pulses, holds 1s, fades out on the LED matrix.

- [ ] **Step 3: Smoke-test unplug animation manually**

Run: `ledmatrix-charging unplug`

Expected: bolt appears then clears column by column from right to left.

- [ ] **Step 4: Commit**

```bash
git add scripts/ledmatrix/ledmatrix/charging.py
git commit -m "feat: add ledmatrix charging animation"
```

---

### Task 4: monitor animation

**Files:**
- Create: `scripts/ledmatrix/ledmatrix/monitor.py`

Rectangle outline 28×7, top-left at row=1, col=3. Expand from center on connect; contract to center on disconnect.

- [ ] **Step 1: Create `scripts/ledmatrix/ledmatrix/monitor.py`**

```python
import argparse
import time
from ledmatrix import Matrix, ROWS, COLS

_RECT_R = 1
_RECT_C = 3
_RECT_H = 7
_RECT_W = 28

def _rect_pixels(r0, c0, h, w):
    px = []
    for c in range(c0, c0 + w):
        px.append((r0, c))
        px.append((r0 + h - 1, c))
    for r in range(r0 + 1, r0 + h - 1):
        px.append((r, c0))
        px.append((r, c0 + w - 1))
    return px

def _connect(dev):
    cr = _RECT_R + _RECT_H // 2
    cc = _RECT_C + _RECT_W // 2

    stages = [
        _rect_pixels(cr, cc, 1, 1),
        _rect_pixels(cr - 1, cc - 2, 3, 5),
        _rect_pixels(cr - 2, cc - 6, 5, 13),
        _rect_pixels(cr - 3, cc - 13, 7, 27),
        _rect_pixels(_RECT_R, _RECT_C, _RECT_H, _RECT_W),
    ]

    for px in stages:
        m = Matrix()
        for r, c in px:
            m.set(r, c, 255)
        m.send(dev)
        time.sleep(0.06)

    # Solid fill 100ms
    m = Matrix()
    for r in range(_RECT_R, _RECT_R + _RECT_H):
        for c in range(_RECT_C, _RECT_C + _RECT_W):
            m.set(r, c, 255)
    m.send(dev)
    time.sleep(0.1)

    # Fade out
    for b in [180, 120, 60, 0]:
        m = Matrix()
        for r in range(_RECT_R, _RECT_R + _RECT_H):
            for c in range(_RECT_C, _RECT_C + _RECT_W):
                m.set(r, c, b)
        m.send(dev)
        time.sleep(0.07)

def _disconnect(dev):
    cr = _RECT_R + _RECT_H // 2
    cc = _RECT_C + _RECT_W // 2

    stages = [
        _rect_pixels(_RECT_R, _RECT_C, _RECT_H, _RECT_W),
        _rect_pixels(cr - 3, cc - 13, 7, 27),
        _rect_pixels(cr - 2, cc - 6, 5, 13),
        _rect_pixels(cr - 1, cc - 2, 3, 5),
        _rect_pixels(cr, cc, 1, 1),
    ]

    for px in stages:
        m = Matrix()
        for r, c in px:
            m.set(r, c, 255)
        m.send(dev)
        time.sleep(0.07)

    # Final blank
    m = Matrix()
    m.send(dev)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["connect", "disconnect"])
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()
    if args.action == "connect":
        _connect(args.dev)
    else:
        _disconnect(args.dev)
```

- [ ] **Step 2: Smoke-test connect animation**

Run: `ledmatrix-monitor connect`

Expected: rectangle expands from center outward, fills solid briefly, fades.

- [ ] **Step 3: Smoke-test disconnect animation**

Run: `ledmatrix-monitor disconnect`

Expected: rectangle contracts to a center point and vanishes.

- [ ] **Step 4: Commit**

```bash
git add scripts/ledmatrix/ledmatrix/monitor.py
git commit -m "feat: add ledmatrix monitor connect/disconnect animation"
```

---

### Task 5: network animation

**Files:**
- Create: `scripts/ledmatrix/ledmatrix/network.py`

Arcs radiate from left edge (wifi) or center (vpn). Each arc is a thin ring drawn by checking distance from origin.

- [ ] **Step 1: Create `scripts/ledmatrix/ledmatrix/network.py`**

```python
import argparse
import math
import time
from ledmatrix import Matrix, ROWS, COLS

def _arc_pixels(origin_r, origin_c, radius):
    px = []
    for r in range(ROWS):
        for c in range(COLS):
            d = math.sqrt((r - origin_r) ** 2 + (c - origin_c) ** 2)
            if abs(d - radius) < 0.8:
                px.append((r, c))
    return px

def _animate_arcs(dev, radii, origin_r, origin_c, reverse=False):
    # Each arc fades over 4 frames (200ms each), next arc starts 1 frame after previous
    FADE = [255, 180, 90, 20, 0]
    FRAME_MS = 0.1

    arc_pixels = [_arc_pixels(origin_r, origin_c, r) for r in radii]
    if reverse:
        arc_pixels = list(reversed(arc_pixels))

    total_frames = len(radii) + len(FADE) - 1

    for frame in range(total_frames):
        m = Matrix()
        for arc_i, px in enumerate(arc_pixels):
            arc_start = arc_i
            fade_idx = frame - arc_start
            if 0 <= fade_idx < len(FADE):
                b = FADE[fade_idx]
                for r, c in px:
                    m.set(r, c, b)
        m.send(dev)
        time.sleep(FRAME_MS)

    # Blink a dot twice at origin on disconnect
    if reverse:
        for _ in range(2):
            m = Matrix()
            m.set(origin_r, min(origin_c, COLS - 1), 255)
            m.send(dev)
            time.sleep(0.15)
            m = Matrix()
            m.send(dev)
            time.sleep(0.15)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("direction", choices=["up", "down"])
    parser.add_argument("--mode", choices=["wifi", "vpn"], default="wifi")
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    if args.mode == "wifi":
        origin_r, origin_c = 4, 0
    else:
        origin_r, origin_c = 4, 17

    radii = [5, 10, 15, 20]
    _animate_arcs(args.dev, radii, origin_r, origin_c, reverse=(args.direction == "down"))
```

- [ ] **Step 2: Smoke-test wifi up**

Run: `ledmatrix-network up --mode wifi`

Expected: arcs expand from left edge outward, each fading as the next appears.

- [ ] **Step 3: Smoke-test wifi down**

Run: `ledmatrix-network down --mode wifi`

Expected: arcs contract inward, two blinks at origin, then clear.

- [ ] **Step 4: Commit**

```bash
git add scripts/ledmatrix/ledmatrix/network.py
git commit -m "feat: add ledmatrix network arc animation"
```

---

### Task 6: notify animation

**Files:**
- Create: `scripts/ledmatrix/ledmatrix/notify.py`

- [ ] **Step 1: Create `scripts/ledmatrix/ledmatrix/notify.py`**

```python
import argparse
import time
from ledmatrix import Matrix, ROWS, COLS

# Envelope: 7 wide x 5 tall
_ENVELOPE = set()
for _c in range(7):
    _ENVELOPE.add((0, _c))
    _ENVELOPE.add((4, _c))
for _r in range(5):
    _ENVELOPE.add((_r, 0))
    _ENVELOPE.add((_r, 6))
# V-fold from top corners to center of row 2
_ENVELOPE.update([(1, 1), (1, 5), (2, 2), (2, 3), (2, 4)])

# Question mark: 3 wide x 5 tall
_QUESTION = [
    (0, 0), (0, 1), (0, 2),
    (1, 2),
    (2, 1), (2, 2),
    (4, 1),
]

def _show(pixels, row_offset, col_offset, dev, duration_ms):
    m = Matrix()
    for r, c in pixels:
        m.set(r + row_offset, c + col_offset, 255)
    m.send(dev)
    time.sleep(duration_ms / 1000)

    # Fade out over 300ms in 10 steps
    for b in [230, 200, 170, 140, 110, 80, 50, 30, 10, 0]:
        m = Matrix()
        for r, c in pixels:
            m.set(r + row_offset, c + col_offset, b)
        m.send(dev)
        time.sleep(0.03)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--type", choices=["message", "question"], default="message")
    parser.add_argument("--duration", type=int, default=2000)
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    if args.type == "message":
        pixels = list(_ENVELOPE)
        row_offset = (ROWS - 5) // 2
        col_offset = (COLS - 7) // 2
    else:
        pixels = _QUESTION
        row_offset = (ROWS - 5) // 2
        col_offset = (COLS - 3) // 2

    _show(pixels, row_offset, col_offset, args.dev, args.duration)
```

- [ ] **Step 2: Smoke-test message type**

Run: `ledmatrix-notify --type message`

Expected: small envelope outline appears centered on the matrix, holds 2s, fades out.

- [ ] **Step 3: Smoke-test question type**

Run: `ledmatrix-notify --type question`

Expected: `?` glyph appears centered, holds 2s, fades out.

- [ ] **Step 4: Commit**

```bash
git add scripts/ledmatrix/ledmatrix/notify.py
git commit -m "feat: add ledmatrix notify animation"
```

---

### Task 7: Nix packaging

**Files:**
- Modify: `modules/packages.nix`

- [ ] **Step 1: Add `ledmatrix-pkg` derivation to `modules/packages.nix`**

Add a `let` block before the `{` opening brace at line 1:

```nix
{ config, pkgs, lib, user, ... }:

let
  ledmatrix-pkg = pkgs.python3Packages.buildPythonPackage {
    pname = "ledmatrix";
    version = "0.1.0";
    src = ../scripts/ledmatrix;
    pyproject = true;
    build-system = [ pkgs.python3Packages.setuptools ];
    propagatedBuildInputs = [ pkgs.python3Packages.pyserial ];
  };
in
```

- [ ] **Step 2: Add `ledmatrix-pkg` to `home.packages`**

Add `ledmatrix-pkg` to the `home.packages` list after the `spotify` entry:

```nix
    ledmatrix-pkg
```

- [ ] **Step 3: Verify Nix eval**

Run:
```bash
nix eval /home/jymdo/Projects/nix-conf#homeConfigurations.$(whoami).config.home.packages --apply 'ps: builtins.any (p: p.pname or "" == "ledmatrix") ps' 2>&1
```

Expected: `true`

- [ ] **Step 4: Commit**

```bash
git add modules/packages.nix
git commit -m "feat: package ledmatrix as Nix derivation"
```

---

### Task 8: Volume trigger (pactl watcher service)

**Files:**
- Modify: `modules/services.nix`

- [ ] **Step 1: Add `volumeWatchScript` and `ledmatrix-volume` service to `modules/services.nix`**

Add the script to the `let` block after `micFixScript`:

```nix
  volumeWatchScript = pkgs.writeShellScript "ledmatrix-volume-watch" ''
    set -euo pipefail
    ${pkgs.pulseaudio}/bin/pactl subscribe 2>/dev/null | while IFS= read -r line; do
      case "$line" in
        *"'change' on sink"*)
          VOL=$(${pkgs.pulseaudio}/bin/pactl get-sink-volume @DEFAULT_SINK@ \
            | grep -oP '\d+(?=%)' | head -1)
          [ -n "$VOL" ] && ledmatrix-bar "$VOL" &
          ;;
      esac
    done
  '';
```

Add the service after the `aw-awatcher` service block:

```nix
  systemd.user.services.ledmatrix-volume-watch = {
    Unit = {
      Description = "LED matrix volume bar trigger";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${volumeWatchScript}";
      Restart = "on-failure";
      RestartSec = "3s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
```

- [ ] **Step 2: Commit**

```bash
git add modules/services.nix
git commit -m "feat: add ledmatrix volume watcher service"
```

---

### Task 9: Brightness trigger (waybar)

**Files:**
- Modify: `modules/waybar.nix`

The existing `brightnessScript` in `modules/waybar.nix` handles both internal (`eDP-1`) and external monitors. We append a `ledmatrix-bar` call after each brightness change.

- [ ] **Step 1: Read the current brightnessScript end of internal branch in `modules/waybar.nix`**

Find the `up)` case inside the `eDP-1` branch (around line 22):

```nix
        up)
          if [ "$PCT" -ge 100 ]; then
            ${pkgs.brightnessctl}/bin/brightnessctl s 0 -q
            ${pkgs.swayosd}/bin/swayosd-client --brightness lower 2>/dev/null || true
          else
            ${pkgs.swayosd}/bin/swayosd-client --brightness raise 2>/dev/null || true
          fi
          ;;
        down) ${pkgs.swayosd}/bin/swayosd-client --brightness lower 2>/dev/null || true ;;
```

- [ ] **Step 2: Append `ledmatrix-bar` call after both internal cases**

Replace the `up)/down)` block inside the `eDP-1` branch with:

```nix
        up)
          if [ "$PCT" -ge 100 ]; then
            ${pkgs.brightnessctl}/bin/brightnessctl s 0 -q
            ${pkgs.swayosd}/bin/swayosd-client --brightness lower 2>/dev/null || true
          else
            ${pkgs.swayosd}/bin/swayosd-client --brightness raise 2>/dev/null || true
          fi
          ;;
        down) ${pkgs.swayosd}/bin/swayosd-client --brightness lower 2>/dev/null || true ;;
      esac
      NEW_PCT=$(( $(${pkgs.brightnessctl}/bin/brightnessctl g) * 100 / $(${pkgs.brightnessctl}/bin/brightnessctl m) ))
      ledmatrix-bar "$NEW_PCT" &
```

The `ledmatrix-bar` call must go after the `esac` that closes the `up/down` case, but still inside the `if [ "$ACTIVE_MON" = "eDP-1" ]` branch, before the outer `else`.

- [ ] **Step 3: Verify eval passes**

Run:
```bash
nix eval /home/jymdo/Projects/nix-conf#homeConfigurations.$(whoami).config.programs.waybar.enable 2>&1
```

Expected: `true`

- [ ] **Step 4: Commit**

```bash
git add modules/waybar.nix
git commit -m "feat: trigger ledmatrix bar on brightness change"
```

---

### Task 10: Charging trigger (udev + ac-monitor service)

**Files:**
- Modify: `modules/services.nix`
- Modify: `modules/hardware/fw16.nix`

The existing `acMonitorScript` in `services.nix` already fires on plug/unplug events. We extend it to also call `ledmatrix-charging`. The udev rule ensures the animation fires even before the user service is ready (belt-and-suspenders; primary trigger is the service).

- [ ] **Step 1: Extend `acMonitorScript` in `modules/services.nix`**

Find the `if [ "$ONLINE" = "1" ]` block in `acMonitorScript` and add `ledmatrix-charging` calls:

```nix
        if [ "$ONLINE" = "1" ]; then
          ${pkgs.libnotify}/bin/notify-send -u low -t 3000 "󰚥 AC Connected" "Plugged in"
          ledmatrix-charging plug &
        elif [ "$ONLINE" = "0" ]; then
          ${pkgs.libnotify}/bin/notify-send -u low -t 3000 "󰁾 AC Disconnected" "Running on battery"
          ledmatrix-charging unplug &
        fi
```

- [ ] **Step 2: Commit**

```bash
git add modules/services.nix
git commit -m "feat: trigger ledmatrix charging animation on AC plug/unplug"
```

---

### Task 11: Monitor connect trigger (Hyprland IPC service)

**Files:**
- Modify: `modules/services.nix`

- [ ] **Step 1: Add `monitorWatchScript` and service to `modules/services.nix`**

Add to the `let` block:

```nix
  monitorWatchScript = pkgs.writeShellScript "ledmatrix-monitor-watch" ''
    set -euo pipefail
    SOCK="/tmp/hypr/''${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
    socat - "UNIX-CONNECT:$SOCK" | while IFS= read -r line; do
      case "$line" in
        monitoradded*)   ledmatrix-monitor connect & ;;
        monitorremoved*) ledmatrix-monitor disconnect & ;;
      esac
    done
  '';
```

Add the service:

```nix
  systemd.user.services.ledmatrix-monitor-watch = {
    Unit = {
      Description = "LED matrix monitor connect/disconnect trigger";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${monitorWatchScript}";
      Restart = "on-failure";
      RestartSec = "3s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
```

Also add `pkgs.socat` to `home.packages` in `modules/packages.nix` if not already present.

- [ ] **Step 2: Check if socat is already in packages**

Run: `grep -n "socat" /home/jymdo/Projects/nix-conf/modules/packages.nix`

If not found, add `socat` to `home.packages`.

- [ ] **Step 3: Commit**

```bash
git add modules/services.nix modules/packages.nix
git commit -m "feat: trigger ledmatrix monitor animation on display connect/disconnect"
```

---

### Task 12: WiFi trigger (NetworkManager dispatcher)

**Files:**
- Modify: `configuration.nix`

NixOS exposes `networking.networkmanager.dispatcherScripts` for scripts run by the NM dispatcher daemon.

- [ ] **Step 1: Add dispatcher script to `configuration.nix`**

Add after the `networking.networkmanager.enable = true;` line:

```nix
  networking.networkmanager.dispatcherScripts = [
    {
      source = pkgs.writeShellScript "nm-ledmatrix" ''
        IFACE="$1"
        ACTION="$2"
        [ "$IFACE" = "lo" ] && exit 0
        case "$ACTION" in
          up)   ledmatrix-network up   --mode wifi & ;;
          down) ledmatrix-network down --mode wifi & ;;
        esac
      '';
      type = "basic";
    }
  ];
```

- [ ] **Step 2: Verify system eval passes**

Run:
```bash
nix eval /home/jymdo/Projects/nix-conf#nixosConfigurations.$(hostname).config.networking.networkmanager.enable 2>&1
```

Expected: `true`

- [ ] **Step 3: Commit**

```bash
git add configuration.nix
git commit -m "feat: trigger ledmatrix network animation on wifi up/down"
```

---

### Task 13: Tailscale trigger (systemd poller)

**Files:**
- Modify: `modules/services.nix`

Poll `tailscale status` every 5 seconds and fire the animation on state change.

- [ ] **Step 1: Add `tailscaleWatchScript` and service to `modules/services.nix`**

Add to the `let` block:

```nix
  tailscaleWatchScript = pkgs.writeShellScript "ledmatrix-tailscale-watch" ''
    set -euo pipefail
    STATE_FILE="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-tailscale-state"
    PREV=$(cat "$STATE_FILE" 2>/dev/null || echo "unknown")

    while true; do
      if ${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null \
           | ${pkgs.jq}/bin/jq -e '.BackendState == "Running"' > /dev/null 2>&1; then
        CUR="up"
      else
        CUR="down"
      fi

      if [ "$CUR" != "$PREV" ]; then
        echo "$CUR" > "$STATE_FILE"
        ledmatrix-network "$CUR" --mode vpn &
        PREV="$CUR"
      fi

      sleep 5
    done
  '';
```

Add the service:

```nix
  systemd.user.services.ledmatrix-tailscale-watch = {
    Unit = {
      Description = "LED matrix tailscale state trigger";
      After = [ "graphical-session.target" "network-online.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${tailscaleWatchScript}";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
```

- [ ] **Step 2: Commit**

```bash
git add modules/services.nix
git commit -m "feat: trigger ledmatrix network animation on tailscale state change"
```

---

### Task 14: Notify trigger (swaync script)

**Files:**
- Modify: `modules/desktop.nix`

swaync exposes a `scripts` map in its settings. Each script entry runs a command when a notification is received by a matching app.

- [ ] **Step 1: Add ledmatrix script to swaync settings in `modules/desktop.nix`**

Find the `scripts` block inside `services.swaync.settings`:

```nix
      scripts = {
        "notification-sound" = {
          exec = "canberra-gtk-play -i message-new-instant -d notification";
          app-name = ".*";
          run-on = "receive";
        };
      };
```

Add the ledmatrix entry:

```nix
      scripts = {
        "notification-sound" = {
          exec = "canberra-gtk-play -i message-new-instant -d notification";
          app-name = ".*";
          run-on = "receive";
        };
        "ledmatrix-notify" = {
          exec = "ledmatrix-notify --type message &";
          app-name = ".*";
          run-on = "receive";
        };
      };
```

- [ ] **Step 2: Verify eval passes**

Run:
```bash
nix eval /home/jymdo/Projects/nix-conf#homeConfigurations.$(whoami).config.services.swaync.enable 2>&1
```

Expected: `true`

- [ ] **Step 3: Commit**

```bash
git add modules/desktop.nix
git commit -m "feat: trigger ledmatrix notify animation on notification receive"
```

---

### Task 15: Build, switch, and test

- [ ] **Step 1: Full build**

Run:
```bash
sudo nixos-rebuild build --flake /home/jymdo/Projects/nix-conf#$(hostname)
```

Expected: build succeeds with no errors.

- [ ] **Step 2: Switch**

Run:
```bash
sudo nixos-rebuild switch --flake /home/jymdo/Projects/nix-conf#$(hostname)
```

Expected: switch succeeds. All new systemd user services start automatically.

- [ ] **Step 3: Verify services are running**

Run:
```bash
systemctl --user status ledmatrix-volume-watch ledmatrix-monitor-watch ledmatrix-tailscale-watch
```

Expected: all three show `active (running)`.

- [ ] **Step 4: Test volume bar**

Scroll volume up/down (e.g. with the volume keys or waybar scroll). Expected: snake bar appears on the LED matrix, animates in/out, clears after 3 seconds.

- [ ] **Step 5: Test brightness bar**

Scroll brightness up/down via the waybar backlight module. Expected: snake bar appears, clears after 3 seconds.

- [ ] **Step 6: Test charging**

Unplug the charger. Expected: lightning bolt appears with unplug animation. Replug. Expected: plug animation plays.

- [ ] **Step 7: Test monitor connect**

Connect or disconnect an external monitor. Expected: rectangle expands or contracts on the LED matrix.

- [ ] **Step 8: Test wifi**

Toggle WiFi off and on (via `nmcli radio wifi off && sleep 2 && nmcli radio wifi on`). Expected: arc-down animation then arc-up animation.

- [ ] **Step 9: Test notify**

Send a test notification: `notify-send "Test" "LED matrix trigger"`. Expected: envelope glyph appears on the matrix.

- [ ] **Step 10: Final fixup commit if needed**

```bash
git add -p
git commit -m "fix: ledmatrix animation adjustments"
```
