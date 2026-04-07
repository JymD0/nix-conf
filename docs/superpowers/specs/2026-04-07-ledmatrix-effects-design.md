# LED Matrix Visual Effects

Five new looping ambient effects added to the LED matrix fuzzel menu.

## Architecture

Each effect is a standalone Python module in `scripts/ledmatrix/ledmatrix/`. They loop continuously at ~25fps until killed. On startup each effect writes its PID to `$XDG_RUNTIME_DIR/ledmatrix-<name>.pid` and removes it on exit. This matches the existing Scroll pattern.

New modules: `fire.py`, `plasma.py`, `rain.py`, `metaballs.py`, `starfield.py`. Each gets a `console_scripts` entry in `pyproject.toml`.

Display constants: 9 columns × 34 rows, brightness 0–255 per pixel.

## Effects

### Fire

Seeds the bottom 2 rows each frame with random brightness (200–255). For every pixel above row 31, computes new brightness as the average of the three pixels one row below (left, center, right) minus a cooling offset (4–8). Result naturally scrolls heat upward and dissipates to black near the top.

Frame rate: 0.04s. No arguments.

### Plasma

Each pixel's brightness per frame:

```
b = (sin(r/4 + t) + sin(c/2 + t*0.7) + sin((r+c)/5 + t*0.5)) / 3
```

Normalized from [-1, 1] to [0, 255]. `t` increments by 0.15 each frame. Produces flowing sinusoidal interference patterns.

Frame rate: 0.04s. No arguments.

### Matrix Rain

Each of the 9 columns maintains a head position (float row index) and speed (randomly 0.4–1.2 rows/frame). The head pixel is drawn at full brightness; the N pixels behind it fade exponentially. When a head exits the bottom it resets above the top with a new random speed and trail length (8–18 pixels). Columns are initialized at staggered starting positions so they don't all arrive together.

Frame rate: 0.04s. No arguments.

### Metaballs

Three blobs drift slowly within the display, each with a position and velocity vector. Velocities are randomized at startup (0.05–0.15 px/frame) and reverse on hitting edges. Each frame, every pixel's brightness:

```
influence = sum(blob.radius**2 / max(dist(pixel, blob)**2, 1) for blob in blobs)
brightness = clamp(influence * scale, 0, 255)
```

Scale is tuned so two blobs at average distance produce ~180 brightness. Blobs merge and separate naturally.

Frame rate: 0.05s. No arguments.

### Starfield

Pool of 30 stars, each with 3D coordinates `(x, y, z)`. `x` and `y` are centered on the display (±4 cols, ±17 rows), `z` is depth (1.0–max_z). Each frame `z` decreases by the star's speed. Project to screen:

```
col = round(x / z * scale + 4)
row = round(y / z * scale + 17)
brightness = round(255 * (1 - z / max_z))
```

Stars that go off-screen or reach `z < 0.5` respawn at a random position with max depth. Creates a 3D flythrough effect.

Frame rate: 0.04s. No arguments.

## Menu integration

Five new entries added to the fuzzel prompt between Scroll and Stop. Each entry kills all six ambient PID files (fire, plasma, rain, metaballs, starfield, scroll) before launching its own process in the background.

Stop is expanded to kill all six PID files, then sends `ctrl exit` as before.

Updated prompt line:

```
Snake | Pong | Game of Life | Weather | Mood | Text | Scroll | Fire | Plasma | Rain | Metaballs | Starfield | Stop
```

Kill helper pattern (per entry):

```shell
for f in fire plasma rain metaballs starfield scroll; do
  pf="${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$f.pid"
  [ -f "$pf" ] && kill "$(cat "$pf")" 2>/dev/null || true
done
```

## Files changed

- `scripts/ledmatrix/ledmatrix/fire.py` — new
- `scripts/ledmatrix/ledmatrix/plasma.py` — new
- `scripts/ledmatrix/ledmatrix/rain.py` — new
- `scripts/ledmatrix/ledmatrix/metaballs.py` — new
- `scripts/ledmatrix/ledmatrix/starfield.py` — new
- `scripts/ledmatrix/pyproject.toml` — add 5 console_scripts entries
- `modules/hyprland.nix` — expand menu prompt and case block, expand Stop handler
