# LED Matrix Animations Design

## Overview

A shared Python package (`ledmatrix`) that models the Framework 16 LED matrix as a
9×34 brightness grid and provides a small set of event-driven animations. Each animation
is a CLI entry point triggered by systemd, udev, or shell hooks.

The matrix is 9 rows × 34 columns, landscape orientation. Each pixel is 0–255 brightness.
Serial protocol: magic `[0x32, 0xAC]` + command byte + 306 brightness bytes over
`/dev/ttyACM0` at 115200 baud.

## Package structure

```
scripts/ledmatrix/
  ledmatrix/
    __init__.py     # Matrix class, send_frame, serial protocol
    bar.py          # snake bar (volume, brightness)
    charging.py     # lightning bolt (plug/unplug)
    monitor.py      # rectangle expand/contract (monitor connect/disconnect)
    network.py      # arc ping (wifi/tailscale up/down)
    notify.py       # envelope or question mark glyph
  setup.py
```

Built as a `buildPythonPackage` derivation in `modules/packages.nix`. Only dependency:
`pyserial`. Resulting binaries (`ledmatrix-bar`, `ledmatrix-charging`, etc.) added to
`home.packages`.

## Matrix class API

```python
ROWS = 9
COLS = 34

class Matrix:
    buf: list[list[int]]          # [row][col], values 0-255

    def clear(self)               # zero all pixels
    def fill(self, brightness=255)
    def set(self, row, col, brightness)   # clamps to 0-255
    def get(self, row, col) -> int
    def snake_pos(self, index) -> tuple[int, int]  # boustrophedon index to (row, col)
    def send(self, dev="/dev/ttyACM0")    # write frame to serial, opens and closes port
```

`snake_pos(i)` converts a linear index (0–305) to grid coordinates following the
left-right / right-left boustrophedon path. Row 0 goes left-to-right, row 1
right-to-left, etc.

`send()` writes `[0x32, 0xAC, FRAME_CMD] + 306 bytes` then closes the port.
`FRAME_CMD` (the "blit full frame" command byte) must be confirmed against the
`inputmodule-rs` source before implementation. Games plan uses `0x10`/`0x11`; blit
is likely `0x0E`.

## Animations

### bar — snake bar for levels (volume, brightness)

```
ledmatrix-bar <value> [--prev <value>] [--dev /dev/ttyACM0]
```

`value` is 0–100. `n_lit = round(value / 100 * 306)`. The lit pixels follow the
boustrophedon path from index 0 upward.

`--prev` is the previous value. If omitted, the script reads
`$XDG_RUNTIME_DIR/ledmatrix-bar-state` to determine the delta.

Animation on increase: each new pixel drops in from the top edge, animating from
`row=0` at the pixel's column down to its final row over ~3 frames at 30ms per frame.
Multiple new pixels animate simultaneously.

Animation on decrease: the removed pixel slides upward off the top edge the same way.

After 3 seconds with no further changes, a systemd timer fires `ledmatrix-bar --clear`
to blank the display.

### charging — lightning bolt

```
ledmatrix-charging <plug|unplug>
```

A lightning bolt sprite (~5 cols wide, 7 rows tall) centered on the 34×9 grid.

`plug`: bolt flashes in at full brightness, dims to ~180, pulses once back to 255
then holds for 1s and fades.

`unplug`: bolt appears briefly then pixels clear from bottom to top in a staggered
column wipe over ~300ms.

### monitor — rectangle outline

```
ledmatrix-monitor <connect|disconnect>
```

A 28×7 rectangle outline centered on the grid (3-pixel margin each side horizontally,
1-pixel vertically).

`connect`: outline expands from a single center point outward corner by corner, then
briefly fills solid (~100ms) and fades over 300ms.

`disconnect`: outline contracts back to a center point and vanishes over 300ms.

### network — arc ping

```
ledmatrix-network <up|down> [--mode wifi|vpn]
```

`--mode wifi`: arcs radiate from the left edge (signal source on the left).
`--mode vpn`: arcs radiate from the center (mesh/tunnel feel).

`up`: 3–4 concentric arcs expand outward one by one, each fading as the next
appears. Total duration ~800ms.

`down`: same arcs but contracting inward, ending with a single dot that blinks
twice then clears. Total duration ~800ms.

### notify — envelope or question mark

```
ledmatrix-notify [--type message|question] [--duration <ms>]
```

`--type message` (default): a 7×5 pixel envelope outline with a diagonal fold line
across the top third.

`--type question`: a pixel-art `?` glyph (~3 cols wide, 5 rows tall) centered on
the grid.

Both appear instantly, hold for `--duration` ms (default 2000), then fade over 300ms.

## Triggering

| Animation | Mechanism |
|---|---|
| `ledmatrix-bar` (volume) | systemd user service running `pactl subscribe`, parses sink volume events |
| `ledmatrix-bar` (brightness) | appended to existing waybar brightness scroll script |
| `ledmatrix-charging` | udev rule on `SUBSYSTEM=="power_supply"` `ATTR{online}` change |
| `ledmatrix-monitor` | Hyprland IPC listener on `monitoradded` / `monitorremoved` events |
| `ledmatrix-network` (wifi) | NetworkManager dispatcher script in `/etc/NetworkManager/dispatcher.d/` |
| `ledmatrix-network` (vpn) | `tailscaled` journal watcher or `tailscale status` poller as systemd user service |
| `ledmatrix-notify` | dunst `script` action in dunstrc, called on notification arrival |

## Nix integration

The `ledmatrix` package is defined in `modules/packages.nix` as a
`pkgs.python3Packages.buildPythonPackage` derivation sourced from
`./scripts/ledmatrix`. It is added to `home.packages`.

The `pactl subscribe` watcher and tailscale poller run as `systemd.user.services`.
The NetworkManager dispatcher script is added via `networking.networkmanager` config.
The udev rule for charging is added to `services.udev.extraRules` in `modules/hardware/fw16.nix`.
The dunst script hook is set in the dunst HM config.
