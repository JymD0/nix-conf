# LED Matrix Waybar Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `custom/ledmatrix` waybar module that shows current brightness, toggles sleep on click, and adjusts brightness on scroll — only visible when `/dev/ttyACM0` is present, only on the laptop bar.

**Architecture:** Three `pkgs.writeShellScript` helpers added to the `let` block of `modules/waybar.nix`. The status script outputs JSON or nothing (hides the module). Sleep state is tracked via a file in `$XDG_RUNTIME_DIR` since the `--sleeping` GET command times out. Signal 9 is used for immediate waybar refresh after toggle/scroll.

**Tech Stack:** Bash, `inputmodule-control`, waybar `custom/*` module

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `modules/waybar.nix` | Modify | Add 3 scripts to `let` block, add module def to `sharedModules`, add to `sharedLayout.modules-right`, add CSS |

---

### Task 1: Add the three scripts to the let block

**Files:**
- Modify: `modules/waybar.nix` (let block, before `in` on line 177)

- [ ] **Step 1: Add `ledmatrixStatusScript` after the `timetrackScript` definition (before `in {`)**

Insert after line 175 (`  '';`) and before `in`:

```nix
  # Show LED matrix brightness; hides when /dev/ttyACM0 is absent
  ledmatrixStatusScript = pkgs.writeShellScript "ledmatrix-status" ''
    DEV="/dev/ttyACM0"
    [ ! -e "$DEV" ] && exit 0
    STATEFILE="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-sleeping"
    RAW=$(inputmodule-control --serial-dev "$DEV" led-matrix --brightness 2>/dev/null)
    BRIGHTNESS=$(echo "$RAW" | awk '{print $NF}')
    BRIGHTNESS="''${BRIGHTNESS:-0}"
    if [ -f "$STATEFILE" ]; then
      printf '{"text":"󰿠","tooltip":"LED Matrix: off","class":"off"}\n'
    else
      printf '{"text":"󰿠 %s%%","tooltip":"LED Matrix: %s%%","class":"on"}\n' "$BRIGHTNESS" "$BRIGHTNESS"
    fi
  '';

  # Toggle LED matrix sleep state
  ledmatrixToggleScript = pkgs.writeShellScript "ledmatrix-toggle" ''
    DEV="/dev/ttyACM0"
    [ ! -e "$DEV" ] && exit 0
    STATEFILE="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-sleeping"
    if [ -f "$STATEFILE" ]; then
      inputmodule-control --serial-dev "$DEV" led-matrix --sleeping false
      rm -f "$STATEFILE"
    else
      inputmodule-control --serial-dev "$DEV" led-matrix --sleeping true
      touch "$STATEFILE"
    fi
    pkill -RTMIN+9 waybar 2>/dev/null || true
  '';

  # Adjust LED matrix brightness by ±10%, wakes on scroll-up if sleeping
  ledmatrixBrightnessScript = pkgs.writeShellScript "ledmatrix-brightness" ''
    set -euo pipefail
    DEV="/dev/ttyACM0"
    [ ! -e "$DEV" ] && exit 0
    STATEFILE="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-sleeping"
    STEP=10
    RAW=$(inputmodule-control --serial-dev "$DEV" led-matrix --brightness 2>/dev/null)
    CUR=$(echo "$RAW" | awk '{print $NF}')
    CUR="''${CUR:-50}"
    case "''$1" in
      up)
        NEW=$(( CUR + STEP > 100 ? 100 : CUR + STEP ))
        if [ -f "$STATEFILE" ]; then
          inputmodule-control --serial-dev "$DEV" led-matrix --sleeping false
          rm -f "$STATEFILE"
        fi
        ;;
      down)
        NEW=$(( CUR - STEP < 0 ? 0 : CUR - STEP ))
        ;;
      *) exit 1 ;;
    esac
    inputmodule-control --serial-dev "$DEV" led-matrix --brightness "$NEW"
    pkill -RTMIN+9 waybar 2>/dev/null || true
  '';
```

- [ ] **Step 2: Verify eval passes**

Run:
```bash
nix eval /home/jymdo/Projects/nix-conf#homeConfigurations.$(whoami).config.programs.waybar.enable 2>&1
```

Expected: `true` (no eval errors). If it fails, check the let block braces and that the new scripts are inside `let ... in`.

- [ ] **Step 3: Commit**

```bash
git add modules/waybar.nix
git commit -m "feat: add ledmatrix status, toggle, and brightness scripts to waybar"
```

---

### Task 2: Add the module definition and wire it up

**Files:**
- Modify: `modules/waybar.nix` (`sharedModules`, `sharedLayout.modules-right`, CSS)

- [ ] **Step 1: Add `custom/ledmatrix` to `sharedModules`**

Add after the `"custom/timetrack"` block (after its closing `};` around line 393, before `tray = {`):

```nix
        "custom/ledmatrix" = {
          interval = 3;
          return-type = "json";
          exec = "${ledmatrixStatusScript}";
          signal = 9;
          format = "{}";
          on-click = "${ledmatrixToggleScript}";
          on-scroll-up = "${ledmatrixBrightnessScript} up";
          on-scroll-down = "${ledmatrixBrightnessScript} down";
        };
```

- [ ] **Step 2: Add `custom/ledmatrix` to `sharedLayout.modules-right` after `backlight`**

In the `sharedLayout` block, change `modules-right` from:

```nix
        modules-right = [
          "custom/timetrack"
          "custom/media"
          "custom/youtube-sync"
          "cpu"
          "memory"
          "temperature"
          "pulseaudio"
          "backlight"
          "battery"
```

to:

```nix
        modules-right = [
          "custom/timetrack"
          "custom/media"
          "custom/youtube-sync"
          "cpu"
          "memory"
          "temperature"
          "pulseaudio"
          "backlight"
          "custom/ledmatrix"
          "battery"
```

Note: the `!eDP-1` bar has its own `modules-right` override that doesn't include `backlight` or `custom/ledmatrix`, so this change only affects the laptop bar.

- [ ] **Step 3: Add CSS for the module**

In the `style` string, after the `#backlight` and `#custom-brightness` line:

```css
        #custom-ledmatrix       { color: #bd93f9; padding: 0 10px; }
        #custom-ledmatrix.off   { color: #6272a4; }
```

Also add `#custom-ledmatrix` to the two existing padding-override selector lists for external monitors. Find this block:

```css
        window#waybar:not(.eDP-1) #cpu,
        window#waybar:not(.eDP-1) #memory,
```

and the corresponding one near the bottom that ends with `#custom-power`. Add `window#waybar:not(.eDP-1) #custom-ledmatrix,` to that list (though the module won't appear on external monitors, keeping the list consistent avoids CSS gaps if the layout ever changes).

- [ ] **Step 4: Verify eval still passes**

Run:
```bash
nix eval /home/jymdo/Projects/nix-conf#homeConfigurations.$(whoami).config.programs.waybar.enable 2>&1
```

Expected: `true`

- [ ] **Step 5: Commit**

```bash
git add modules/waybar.nix
git commit -m "feat: add custom/ledmatrix waybar module with brightness and toggle"
```

---

### Task 3: Build, switch, and test

- [ ] **Step 1: Build**

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

Expected: switch succeeds.

- [ ] **Step 3: Restart waybar**

Run:
```bash
pkill waybar; sleep 1; waybar &
```

Or press `SUPER+SHIFT+R` to reload Hyprland (which restarts waybar via exec-once).

- [ ] **Step 4: Verify module appears**

Expected: `󰿠 51%` (or current brightness) visible in the right pill on the laptop bar. No module on external monitors.

- [ ] **Step 5: Test toggle**

Left-click the module. Expected: matrix goes dark, icon changes to `󰿠` (no percentage), colour greys out to `#6272a4`.

Click again. Expected: matrix wakes, percentage reappears, colour returns to `#bd93f9`.

- [ ] **Step 6: Test brightness scroll**

Scroll up on the module. Expected: brightness increases by 10%, tooltip updates. If matrix was sleeping, it wakes.

Scroll down. Expected: brightness decreases by 10%.

- [ ] **Step 7: Test device-absent behaviour**

If you can safely unplug the LED matrix module, do so. Expected: module disappears from waybar entirely. Replug — expected: module reappears within 3 seconds (next poll interval).

- [ ] **Step 8: Final commit if fixups were needed**

```bash
git add modules/waybar.nix
git commit -m "fix: ledmatrix waybar module adjustments"
```
