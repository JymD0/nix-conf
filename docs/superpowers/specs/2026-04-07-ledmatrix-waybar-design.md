# LED Matrix Waybar Module Design

**Goal:** Add a `custom/ledmatrix` waybar module that shows when the FW16 LED matrix is connected, lets the user toggle it on/off, and adjust brightness via scroll.

## Architecture

Single `custom/ledmatrix` waybar module backed by two shell scripts defined in `modules/waybar.nix`:

- `ledmatrixStatusScript` — the polling `exec` script (interval 3s), outputs JSON or empty string
- `ledmatrixToggleScript` — called on left-click, toggles sleep state

State (sleeping vs awake) is tracked via a file at `$XDG_RUNTIME_DIR/ledmatrix-sleeping` because `inputmodule-control --sleeping` (GET) times out unreliably on this hardware.

## Detection

Both scripts check for `/dev/ttyACM0` at the start. If absent, the status script outputs nothing (empty string), which causes waybar to hide the module entirely.

## Status Script

Reads current brightness via `inputmodule-control --serial-dev /dev/ttyACM0 led-matrix --brightness`, parses the integer out of `Current brightness: N`. Checks the state file to determine sleeping status. Outputs:

```json
{"text": "󰿠 51%", "tooltip": "LED Matrix: 51%", "class": "on"}
{"text": "󰿠", "tooltip": "LED Matrix: off", "class": "off"}
```

Icon: `󰿠` (nf-md-led_strip) — always shown, text shows brightness % only when awake.

## Toggle Script

- If state file exists: send `--sleeping false`, delete state file
- If state file absent: send `--sleeping true`, create state file

After toggling, sends `pkill -RTMIN+9 waybar` to force an immediate refresh (using signal 9, one above the youtube-sync module's signal 8).

## Brightness Scroll

Handled inline in the module config (`on-scroll-up`/`on-scroll-down`). Each scroll:
1. Reads current brightness
2. Clamps new value to 0-100
3. Sends `--brightness <new>`
4. If scrolling up and matrix is sleeping, wakes it (deletes state file, sends `--sleeping false`)

Step size: 10%.

## Waybar Config

Module only added to `eDP-1` bar (the laptop screen bar), not the external monitor bar — the matrix is physically part of the laptop chassis.

Placement: after `backlight` in `modules-right`.

CSS: `#custom-ledmatrix { color: #bd93f9; }` (on), `.off { color: #6272a4; }` (sleeping).

## Files Changed

| File | Change |
|------|--------|
| `modules/waybar.nix` | Add `ledmatrixStatusScript`, `ledmatrixToggleScript`, `ledmatrixBrightnessScript` let bindings; add `custom/ledmatrix` module def; add to `eDP-1` `modules-right`; add CSS |
