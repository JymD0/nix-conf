# LED Matrix Game Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fuzzel-based game launcher for the FW16 LED matrix with Hyprland submap key capture during gameplay.

**Architecture:** A bash script sends raw serial bytes (FWK protocol: magic `0x32 0xAC` + command + arg) to `/dev/ttyACM0` for game start and directional controls. A fuzzel dmenu wrapper presents game choices. A Hyprland submap captures arrow keys and WASD during gameplay, routing presses to the serial script. ESC exits the game and releases keys back to normal Hyprland binds.

**Tech Stack:** Bash (serial via `printf`/`stty`), Hyprland submaps, fuzzel `--dmenu`

**Serial Protocol (from Framework inputmodule-rs):**

| Command     | Bytes                    |
|-------------|--------------------------|
| Start Snake | `\x32\xac\x10\x00`      |
| Start Pong  | `\x32\xac\x10\x01`      |
| Start Tetris| `\x32\xac\x10\x02`      |
| Start GoL   | `\x32\xac\x10\x03`      |
| Ctrl Up     | `\x32\xac\x11\x00`      |
| Ctrl Down   | `\x32\xac\x11\x01`      |
| Ctrl Left   | `\x32\xac\x11\x02`      |
| Ctrl Right  | `\x32\xac\x11\x03`      |
| Ctrl Exit   | `\x32\xac\x11\x04`      |

**Prereqs (already done):**
- `inputmodule-control` + udev rules in `modules/hardware/fw16.nix`
- User in `dialout` group for `/dev/ttyACM0` access
- `ledmatrix` shell alias for CLI use

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `modules/hyprland.nix` | Modify | Add `ledmatrixSend` + `ledmatrixMenu` scripts to `let` block, add `SUPER+ALT+G` keybind, add `ledmatrix` submap via `extraConfig` |

Only one file changes. Scripts are defined inline as `pkgs.writeShellScript` (matches existing `monitorWallpaperScript` pattern). The submap goes in `extraConfig` because Hyprland submaps are positional config blocks that the Nix settings attrset doesn't support directly.

---

### Task 1: Add the serial command sender script

**Files:**
- Modify: `modules/hyprland.nix:1-23` (let block)

- [ ] **Step 1: Add `ledmatrixSend` to the let block**

Insert after the `monitorWallpaperScript` definition (after line 21, before `in`):

```nix
  # Send raw serial commands to the FW16 LED matrix module
  ledmatrixSend = pkgs.writeShellScript "ledmatrix-send" ''
    set -euo pipefail
    DEV="/dev/ttyACM0"
    stty -F "$DEV" 115200 raw -echo 2>/dev/null || true
    case "$1:$2" in
      start:snake)        printf '\x32\xac\x10\x00' > "$DEV" ;;
      start:pong)         printf '\x32\xac\x10\x01' > "$DEV" ;;
      start:tetris)       printf '\x32\xac\x10\x02' > "$DEV" ;;
      start:game-of-life) printf '\x32\xac\x10\x03' > "$DEV" ;;
      ctrl:up)            printf '\x32\xac\x11\x00' > "$DEV" ;;
      ctrl:down)          printf '\x32\xac\x11\x01' > "$DEV" ;;
      ctrl:left)          printf '\x32\xac\x11\x02' > "$DEV" ;;
      ctrl:right)         printf '\x32\xac\x11\x03' > "$DEV" ;;
      ctrl:exit)          printf '\x32\xac\x11\x04' > "$DEV" ;;
      *) exit 1 ;;
    esac
  '';
```

- [ ] **Step 2: Verify the script builds**

Run: `nix eval --raw /home/jymdo/Projects/nix-conf#nixosConfigurations.$(hostname).config.system.build.toplevel.drvPath 2>&1 | head -5`

Expected: a store path (no eval errors). If it errors on unresolved references, check that `ledmatrixSend` is inside the existing `let ... in` block.

- [ ] **Step 3: Smoke-test serial commands manually**

Run: `stty -F /dev/ttyACM0 115200 raw -echo && printf '\x32\xac\x10\x00' > /dev/ttyACM0`

Expected: Snake game starts on the LED matrix. If nothing happens, the raw serial approach doesn't work and we need to fall back to Python with pyserial. Stop the game afterward: `printf '\x32\xac\x11\x04' > /dev/ttyACM0`

- [ ] **Step 4: Commit**

```bash
git add modules/hyprland.nix
git commit -m "feat: add ledmatrix serial send script for game control"
```

---

### Task 2: Add the fuzzel game menu script

**Files:**
- Modify: `modules/hyprland.nix:1-23` (let block)

- [ ] **Step 1: Add `ledmatrixMenu` to the let block**

Insert after `ledmatrixSend` in the let block:

```nix
  # Fuzzel picker for LED matrix games, enters Hyprland submap on game start
  ledmatrixMenu = pkgs.writeShellScript "ledmatrix-menu" ''
    set -euo pipefail
    choice=$(printf "Snake\nPong\nTetris\nGame of Life\nStop" | ${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt "LED Matrix  " || true)
    [ -z "$choice" ] && exit 0
    case "$choice" in
      Snake)            ${ledmatrixSend} start snake ;;
      Pong)             ${ledmatrixSend} start pong ;;
      Tetris)           ${ledmatrixSend} start tetris ;;
      "Game of Life")   ${ledmatrixSend} start game-of-life ;;
      Stop)             ${ledmatrixSend} ctrl exit; exit 0 ;;
    esac
    hyprctl dispatch submap ledmatrix
  '';
```

Key behavior:
- Dismissing fuzzel (ESC/click-away) does nothing (empty choice, early exit)
- Picking a game sends the start command, then activates the `ledmatrix` submap
- "Stop" sends the exit command but does NOT enter the submap

- [ ] **Step 2: Commit**

```bash
git add modules/hyprland.nix
git commit -m "feat: add fuzzel game picker menu for LED matrix"
```

---

### Task 3: Add Hyprland keybind and submap

**Files:**
- Modify: `modules/hyprland.nix:147-232` (bind list)
- Modify: `modules/hyprland.nix:263-265` (add extraConfig before closing braces)

- [ ] **Step 1: Add the menu keybind**

Add to the `bind` list, after the emoji picker line (`$mod, Period, exec, bemoji -t`):

```nix
        "$mod ALT, G, exec, ${ledmatrixMenu}"
```

- [ ] **Step 2: Add the ledmatrix submap via extraConfig**

Add `extraConfig` inside `wayland.windowManager.hyprland`, after `settings = { ... };`:

```nix
    extraConfig = ''
      submap = ledmatrix
      bind = , up, exec, ${ledmatrixSend} ctrl up
      bind = , down, exec, ${ledmatrixSend} ctrl down
      bind = , left, exec, ${ledmatrixSend} ctrl left
      bind = , right, exec, ${ledmatrixSend} ctrl right
      bind = , w, exec, ${ledmatrixSend} ctrl up
      bind = , s, exec, ${ledmatrixSend} ctrl down
      bind = , a, exec, ${ledmatrixSend} ctrl left
      bind = , d, exec, ${ledmatrixSend} ctrl right
      bind = , escape, exec, ${ledmatrixSend} ctrl exit
      bind = , escape, submap, reset
      submap = reset
    '';
```

Notes on the submap:
- Arrow keys AND WASD both mapped (either works for gameplay)
- ESC sends the exit command to the LED matrix AND resets the submap (two binds on the same key both fire)
- While in the submap, all other keys are silently dropped (no accidental window switching)
- The user MUST press ESC to return to normal keybinds

- [ ] **Step 3: Commit**

```bash
git add modules/hyprland.nix
git commit -m "feat: add SUPER+ALT+G game menu and ledmatrix submap"
```

---

### Task 4: Build, switch, and test

- [ ] **Step 1: Build the system**

Run: `sudo nixos-rebuild build --flake /etc/nixos#$(hostname)`

Expected: build succeeds with no errors.

- [ ] **Step 2: Switch to the new configuration**

Run: `sudo nixos-rebuild switch --flake /etc/nixos#$(hostname)`

Expected: switch succeeds, Hyprland reloads config.

- [ ] **Step 3: Test the game menu**

Press `SUPER+ALT+G`. Expected: fuzzel pops up with "Snake / Pong / Tetris / Game of Life / Stop".

Pick "Snake". Expected: LED matrix starts showing the snake game, and arrow keys stop working for window management (submap is active).

- [ ] **Step 4: Test game controls**

Press arrow keys and WASD. Expected: the snake responds to directional input on the LED matrix.

- [ ] **Step 5: Test exit**

Press ESC. Expected: LED matrix game stops, normal Hyprland keybinds resume (arrow keys move window focus again).

- [ ] **Step 6: Test dismiss**

Press `SUPER+ALT+G`, then dismiss fuzzel (click outside or press ESC in the menu). Expected: nothing happens, no submap activated.

- [ ] **Step 7: Test Stop option**

Start a game via the menu, then press ESC to exit the submap. Press `SUPER+ALT+G` and pick "Stop". Expected: game stops on the LED matrix (if it was still running on the module firmware).

- [ ] **Step 8: Final commit (if any fixups needed)**

```bash
git add modules/hyprland.nix
git commit -m "fix: ledmatrix game integration adjustments"
```

---

## Fallback: Python approach

If Task 1 Step 3 fails (raw `printf` to `/dev/ttyACM0` doesn't work), replace `ledmatrixSend` with a Python version:

```nix
  ledmatrixPython = pkgs.python3.withPackages (ps: [ ps.pyserial ]);

  ledmatrixSend = pkgs.writeShellScript "ledmatrix-send" ''
    set -euo pipefail
    exec ${ledmatrixPython}/bin/python3 -c "
import sys, serial
s = serial.Serial('/dev/ttyACM0', 115200, timeout=1)
cmds = {
    'start:snake': b'\\x32\\xac\\x10\\x00',
    'start:pong': b'\\x32\\xac\\x10\\x01',
    'start:tetris': b'\\x32\\xac\\x10\\x02',
    'start:game-of-life': b'\\x32\\xac\\x10\\x03',
    'ctrl:up': b'\\x32\\xac\\x11\\x00',
    'ctrl:down': b'\\x32\\xac\\x11\\x01',
    'ctrl:left': b'\\x32\\xac\\x11\\x02',
    'ctrl:right': b'\\x32\\xac\\x11\\x03',
    'ctrl:exit': b'\\x32\\xac\\x11\\x04',
}
key = f'{sys.argv[1]}:{sys.argv[2]}'
s.write(cmds[key])
s.close()
" "$@"
  '';
```

This uses pyserial for proper port handling. The rest of the plan (menu, submap, keybind) stays identical.
