# LED Matrix Visual Effects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add five looping ambient effects (fire, plasma, matrix rain, metaballs, starfield) to the LED matrix fuzzel menu.

**Architecture:** Each effect is a Python module with a pure frame-building function and a `main()` loop that writes a PID file, renders frames at ~25fps, and cleans up on exit. Menu gains five new entries; Stop kills all ambient PID files.

**Tech Stack:** Python 3, `math`/`random` stdlib, existing `ledmatrix.Matrix` class, Nix `pyproject.toml` console_scripts, shell in hyprland.nix.

---

## File map

- Create: `scripts/ledmatrix/ledmatrix/fire.py`
- Create: `scripts/ledmatrix/ledmatrix/plasma.py`
- Create: `scripts/ledmatrix/ledmatrix/rain.py`
- Create: `scripts/ledmatrix/ledmatrix/metaballs.py`
- Create: `scripts/ledmatrix/ledmatrix/starfield.py`
- Create: `scripts/ledmatrix/tests/test_effects.py`
- Modify: `scripts/ledmatrix/pyproject.toml`
- Modify: `modules/hyprland.nix`

---

### Task 1: fire.py

**Files:**
- Create: `scripts/ledmatrix/ledmatrix/fire.py`
- Modify: `scripts/ledmatrix/tests/test_effects.py`

- [ ] **Step 1: Write the failing tests**

Create `scripts/ledmatrix/tests/test_effects.py`:

```python
from ledmatrix import ROWS, COLS, Matrix
from ledmatrix.fire import _step_heat, _build_fire_frame


def _empty_heat():
    return [[0.0] * COLS for _ in range(ROWS)]


def test_step_heat_seeds_bottom_rows():
    heat = _step_heat(_empty_heat())
    assert heat[ROWS - 1][0] >= 180
    assert heat[ROWS - 2][0] >= 160


def test_step_heat_returns_correct_shape():
    heat = _step_heat(_empty_heat())
    assert len(heat) == ROWS
    assert all(len(row) == COLS for row in heat)


def test_step_heat_values_in_range():
    heat = _empty_heat()
    for _ in range(10):
        heat = _step_heat(heat)
    for row in heat:
        for v in row:
            assert 0 <= v <= 255


def test_build_fire_frame_returns_matrix():
    heat = _step_heat(_empty_heat())
    m = _build_fire_frame(heat)
    assert isinstance(m, Matrix)


def test_build_fire_frame_brightness_in_range():
    heat = _step_heat(_empty_heat())
    m = _build_fire_frame(heat)
    for r in range(ROWS):
        for c in range(COLS):
            assert 0 <= m.get(r, c) <= 255
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd scripts/ledmatrix && python -m pytest tests/test_effects.py -v 2>&1 | head -30
```

Expected: `ImportError` — `ledmatrix.fire` not found.

- [ ] **Step 3: Create fire.py**

```python
import argparse
import os
import random
import time
from ledmatrix import Matrix, ROWS, COLS


def _step_heat(heat):
    for c in range(COLS):
        heat[ROWS - 1][c] = random.uniform(200, 255)
        heat[ROWS - 2][c] = random.uniform(180, 240)
    new = [[0.0] * COLS for _ in range(ROWS)]
    for r in range(ROWS - 2):
        for c in range(COLS):
            left   = heat[r + 1][max(0, c - 1)]
            center = heat[r + 1][c]
            right  = heat[r + 1][min(COLS - 1, c + 1)]
            new[r][c] = max(0.0, (left + center + right) / 3 - random.uniform(4, 8))
    new[ROWS - 2] = heat[ROWS - 2][:]
    new[ROWS - 1] = heat[ROWS - 1][:]
    return new


def _build_fire_frame(heat):
    m = Matrix()
    for r in range(ROWS):
        for c in range(COLS):
            m.set(r, c, int(heat[r][c]))
    return m


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    pid_file = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ledmatrix-fire.pid")
    with open(pid_file, "w") as f:
        f.write(str(os.getpid()))

    try:
        heat = [[0.0] * COLS for _ in range(ROWS)]
        while True:
            heat = _step_heat(heat)
            _build_fire_frame(heat).send(args.dev)
            time.sleep(0.04)
    finally:
        try:
            os.unlink(pid_file)
        except OSError:
            pass
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd scripts/ledmatrix && python -m pytest tests/test_effects.py -v 2>&1 | head -30
```

Expected: all fire tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/ledmatrix/ledmatrix/fire.py scripts/ledmatrix/tests/test_effects.py
git commit -m "feat: add fire effect for LED matrix"
```

---

### Task 2: plasma.py

**Files:**
- Create: `scripts/ledmatrix/ledmatrix/plasma.py`
- Modify: `scripts/ledmatrix/tests/test_effects.py`

- [ ] **Step 1: Add failing tests**

Append to `scripts/ledmatrix/tests/test_effects.py`:

```python
from ledmatrix.plasma import _build_plasma_frame


def test_build_plasma_frame_returns_matrix():
    assert isinstance(_build_plasma_frame(0.0), Matrix)


def test_build_plasma_frame_brightness_in_range():
    m = _build_plasma_frame(1.23)
    for r in range(ROWS):
        for c in range(COLS):
            assert 0 <= m.get(r, c) <= 255


def test_build_plasma_frame_changes_with_t():
    m1 = _build_plasma_frame(0.0)
    m2 = _build_plasma_frame(1.0)
    values1 = [m1.get(r, c) for r in range(ROWS) for c in range(COLS)]
    values2 = [m2.get(r, c) for r in range(ROWS) for c in range(COLS)]
    assert values1 != values2
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd scripts/ledmatrix && python -m pytest tests/test_effects.py::test_build_plasma_frame_returns_matrix -v
```

Expected: `ImportError` — `ledmatrix.plasma` not found.

- [ ] **Step 3: Create plasma.py**

```python
import argparse
import math
import os
import time
from ledmatrix import Matrix, ROWS, COLS


def _build_plasma_frame(t):
    m = Matrix()
    for r in range(ROWS):
        for c in range(COLS):
            v = (
                math.sin(r / 4.0 + t) +
                math.sin(c / 2.0 + t * 0.7) +
                math.sin((r + c) / 5.0 + t * 0.5)
            ) / 3.0
            m.set(r, c, int((v + 1) / 2 * 255))
    return m


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    pid_file = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ledmatrix-plasma.pid")
    with open(pid_file, "w") as f:
        f.write(str(os.getpid()))

    try:
        t = 0.0
        while True:
            _build_plasma_frame(t).send(args.dev)
            t += 0.15
            time.sleep(0.04)
    finally:
        try:
            os.unlink(pid_file)
        except OSError:
            pass
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd scripts/ledmatrix && python -m pytest tests/test_effects.py -v -k plasma
```

Expected: all 3 plasma tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/ledmatrix/ledmatrix/plasma.py scripts/ledmatrix/tests/test_effects.py
git commit -m "feat: add plasma wave effect for LED matrix"
```

---

### Task 3: rain.py

**Files:**
- Create: `scripts/ledmatrix/ledmatrix/rain.py`
- Modify: `scripts/ledmatrix/tests/test_effects.py`

- [ ] **Step 1: Add failing tests**

Append to `scripts/ledmatrix/tests/test_effects.py`:

```python
from ledmatrix.rain import _make_column, _build_rain_frame, _step_columns


def test_make_column_has_required_keys():
    col = _make_column()
    assert "pos" in col
    assert "speed" in col
    assert "trail" in col


def test_build_rain_frame_returns_matrix():
    columns = [_make_column() for _ in range(COLS)]
    assert isinstance(_build_rain_frame(columns), Matrix)


def test_build_rain_frame_brightness_in_range():
    columns = [_make_column() for _ in range(COLS)]
    for col in columns:
        col["pos"] = 10.0
    m = _build_rain_frame(columns)
    for r in range(ROWS):
        for c in range(COLS):
            assert 0 <= m.get(r, c) <= 255


def test_step_columns_advances_position():
    columns = [_make_column() for _ in range(COLS)]
    before = [col["pos"] for col in columns]
    _step_columns(columns)
    after = [col["pos"] for col in columns]
    assert all(a >= b for a, b in zip(after, before))
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd scripts/ledmatrix && python -m pytest tests/test_effects.py -v -k rain
```

Expected: `ImportError` — `ledmatrix.rain` not found.

- [ ] **Step 3: Create rain.py**

```python
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd scripts/ledmatrix && python -m pytest tests/test_effects.py -v -k rain
```

Expected: all 4 rain tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/ledmatrix/ledmatrix/rain.py scripts/ledmatrix/tests/test_effects.py
git commit -m "feat: add matrix rain effect for LED matrix"
```

---

### Task 4: metaballs.py

**Files:**
- Create: `scripts/ledmatrix/ledmatrix/metaballs.py`
- Modify: `scripts/ledmatrix/tests/test_effects.py`

- [ ] **Step 1: Add failing tests**

Append to `scripts/ledmatrix/tests/test_effects.py`:

```python
from ledmatrix.metaballs import _make_blob, _build_metaballs_frame, _step_blobs


def test_make_blob_has_required_keys():
    blob = _make_blob()
    for key in ("r", "c", "vr", "vc", "radius"):
        assert key in blob


def test_build_metaballs_frame_returns_matrix():
    blobs = [_make_blob() for _ in range(3)]
    assert isinstance(_build_metaballs_frame(blobs), Matrix)


def test_build_metaballs_frame_brightness_in_range():
    blobs = [_make_blob() for _ in range(3)]
    m = _build_metaballs_frame(blobs)
    for r in range(ROWS):
        for c in range(COLS):
            assert 0 <= m.get(r, c) <= 255


def test_step_blobs_moves_positions():
    blobs = [_make_blob() for _ in range(3)]
    before = [(b["r"], b["c"]) for b in blobs]
    _step_blobs(blobs)
    after = [(b["r"], b["c"]) for b in blobs]
    assert before != after


def test_step_blobs_stays_in_bounds():
    blobs = [_make_blob() for _ in range(3)]
    for _ in range(200):
        _step_blobs(blobs)
    for blob in blobs:
        assert 0 <= blob["r"] < ROWS
        assert 0 <= blob["c"] < COLS
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd scripts/ledmatrix && python -m pytest tests/test_effects.py -v -k metaballs
```

Expected: `ImportError` — `ledmatrix.metaballs` not found.

- [ ] **Step 3: Create metaballs.py**

```python
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd scripts/ledmatrix && python -m pytest tests/test_effects.py -v -k metaballs
```

Expected: all 5 metaballs tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/ledmatrix/ledmatrix/metaballs.py scripts/ledmatrix/tests/test_effects.py
git commit -m "feat: add metaballs effect for LED matrix"
```

---

### Task 5: starfield.py

**Files:**
- Create: `scripts/ledmatrix/ledmatrix/starfield.py`
- Modify: `scripts/ledmatrix/tests/test_effects.py`

- [ ] **Step 1: Add failing tests**

Append to `scripts/ledmatrix/tests/test_effects.py`:

```python
from ledmatrix.starfield import _make_star, _build_starfield_frame, _step_stars, MAX_Z


def test_make_star_has_required_keys():
    star = _make_star()
    for key in ("x", "y", "z", "speed"):
        assert key in star


def test_make_star_z_in_range():
    for _ in range(20):
        star = _make_star()
        assert 0 < star["z"] <= MAX_Z


def test_build_starfield_frame_returns_matrix():
    stars = [_make_star() for _ in range(30)]
    assert isinstance(_build_starfield_frame(stars), Matrix)


def test_build_starfield_frame_brightness_in_range():
    stars = [_make_star() for _ in range(30)]
    m = _build_starfield_frame(stars)
    for r in range(ROWS):
        for c in range(COLS):
            assert 0 <= m.get(r, c) <= 255


def test_step_stars_decrements_z():
    stars = [_make_star() for _ in range(30)]
    before = [s["z"] for s in stars]
    _step_stars(stars)
    after = [s["z"] for s in stars]
    # at least some stars should have moved closer (lower z) or been respawned at MAX_Z
    assert any(a < b or a == MAX_Z for a, b in zip(after, before))
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd scripts/ledmatrix && python -m pytest tests/test_effects.py -v -k starfield
```

Expected: `ImportError` — `ledmatrix.starfield` not found.

- [ ] **Step 3: Create starfield.py**

```python
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd scripts/ledmatrix && python -m pytest tests/test_effects.py -v -k starfield
```

Expected: all 5 starfield tests pass.

- [ ] **Step 5: Run full test suite**

```bash
cd scripts/ledmatrix && python -m pytest -v
```

Expected: all tests pass (existing + new).

- [ ] **Step 6: Commit**

```bash
git add scripts/ledmatrix/ledmatrix/starfield.py scripts/ledmatrix/tests/test_effects.py
git commit -m "feat: add starfield effect for LED matrix"
```

---

### Task 6: Register console_scripts

**Files:**
- Modify: `scripts/ledmatrix/pyproject.toml`

- [ ] **Step 1: Add the five new entry points**

Edit `scripts/ledmatrix/pyproject.toml`. Replace the `[project.scripts]` section:

```toml
[project.scripts]
ledmatrix-bar       = "ledmatrix.bar:main"
ledmatrix-charging  = "ledmatrix.charging:main"
ledmatrix-monitor   = "ledmatrix.monitor:main"
ledmatrix-network   = "ledmatrix.network:main"
ledmatrix-notify    = "ledmatrix.notify:main"
ledmatrix-fire      = "ledmatrix.fire:main"
ledmatrix-plasma    = "ledmatrix.plasma:main"
ledmatrix-rain      = "ledmatrix.rain:main"
ledmatrix-metaballs = "ledmatrix.metaballs:main"
ledmatrix-starfield = "ledmatrix.starfield:main"
```

- [ ] **Step 2: Commit**

```bash
git add scripts/ledmatrix/pyproject.toml
git commit -m "feat: register fire/plasma/rain/metaballs/starfield console scripts"
```

---

### Task 7: Menu integration in hyprland.nix

**Files:**
- Modify: `modules/hyprland.nix`

- [ ] **Step 1: Expand the fuzzel prompt line**

In `modules/hyprland.nix`, find the line (around line 76):

```nix
    choice=$(printf "Snake\nPong\nGame of Life\nWeather\nMood\nText\nScroll\nStop" | $FUZZEL --dmenu --prompt "LED Matrix  " || true)
```

Replace with:

```nix
    choice=$(printf "Snake\nPong\nGame of Life\nWeather\nMood\nText\nScroll\nFire\nPlasma\nRain\nMetaballs\nStarfield\nStop" | $FUZZEL --dmenu --prompt "LED Matrix  " || true)
```

- [ ] **Step 2: Update the Scroll case to kill other ambient effects first**

Find the Scroll case block (around line 132):

```nix
      Scroll)
        t=$(printf "" | $FUZZEL --dmenu --prompt "Scroll text: " || true)
        [ -z "$t" ] && exit 0
        PIDFILE="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-scroll.pid"
        [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null || true
        ${ledmatrixScroll} "$t" &
        exit 0
        ;;
```

Replace with:

```nix
      Scroll)
        t=$(printf "" | $FUZZEL --dmenu --prompt "Scroll text: " || true)
        [ -z "$t" ] && exit 0
        for _f in fire plasma rain metaballs starfield scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          [ -f "$_pf" ] && kill "$(cat "$_pf")" 2>/dev/null || true
        done
        ${ledmatrixScroll} "$t" &
        exit 0
        ;;
```

- [ ] **Step 3: Add the five new case entries**

After the Scroll block (before Stop), add:

```nix
      Fire)
        for _f in fire plasma rain metaballs starfield scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          [ -f "$_pf" ] && kill "$(cat "$_pf")" 2>/dev/null || true
        done
        ledmatrix-fire --dev "$DEV" &
        exit 0
        ;;

      Plasma)
        for _f in fire plasma rain metaballs starfield scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          [ -f "$_pf" ] && kill "$(cat "$_pf")" 2>/dev/null || true
        done
        ledmatrix-plasma --dev "$DEV" &
        exit 0
        ;;

      Rain)
        for _f in fire plasma rain metaballs starfield scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          [ -f "$_pf" ] && kill "$(cat "$_pf")" 2>/dev/null || true
        done
        ledmatrix-rain --dev "$DEV" &
        exit 0
        ;;

      Metaballs)
        for _f in fire plasma rain metaballs starfield scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          [ -f "$_pf" ] && kill "$(cat "$_pf")" 2>/dev/null || true
        done
        ledmatrix-metaballs --dev "$DEV" &
        exit 0
        ;;

      Starfield)
        for _f in fire plasma rain metaballs starfield scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          [ -f "$_pf" ] && kill "$(cat "$_pf")" 2>/dev/null || true
        done
        ledmatrix-starfield --dev "$DEV" &
        exit 0
        ;;
```

- [ ] **Step 4: Expand the Stop case**

Find the current Stop handler:

```nix
      Stop)
        PIDFILE="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-scroll.pid"
        [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null || true
        ${ledmatrixSend} ctrl exit
        exit 0
        ;;
```

Replace with:

```nix
      Stop)
        for _f in fire plasma rain metaballs starfield scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          [ -f "$_pf" ] && kill "$(cat "$_pf")" 2>/dev/null || true
        done
        ${ledmatrixSend} ctrl exit
        exit 0
        ;;
```

- [ ] **Step 5: Commit**

```bash
git add modules/hyprland.nix
git commit -m "feat: add fire/plasma/rain/metaballs/starfield to LED matrix menu"
```
