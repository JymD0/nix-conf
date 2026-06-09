# Sunshine Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate Sunshine remote desktop streaming into the NixOS/Hyprland setup with idle inhibition, Waybar status, LED feedback, and Walker menu entry.

**Architecture:** Sunshine runs as a user service (NixOS module). A watcher service tails its journal for connect/disconnect events, managing hypridle suppression and sleep inhibitors via a shared flag directory. Waybar polls the journal for status. Walker and Waybar link to the web UI.

**Tech Stack:** NixOS 24.11, Home Manager, Hyprland, Waybar, systemd user services, journalctl

**Spec:** `docs/superpowers/specs/2026-06-09-sunshine-integration-design.md`

---

### Task 1: Sunshine NixOS Configuration

**Files:**
- Modify: `configuration.nix:99-104` (existing sunshine block)

- [ ] **Step 1: Add `autoStart` and `hardware.uinput.enable`**

In `configuration.nix`, update the existing sunshine block and add uinput:

```nix
  # Sunshine — remote desktop streaming (use Moonlight client on Windows)
  services.sunshine = {
    enable = true;
    autoStart = true;
    openFirewall = true;
    capSysAdmin = true; # needed for Wayland screen capture
  };

  # uinput device needed for Sunshine's virtual keyboard/mouse/gamepad input
  hardware.uinput.enable = true;
```

- [ ] **Step 2: Verify the config evaluates**

Run: `nix flake check --no-build 2>&1 | head -20`
Expected: no errors (warnings about unfree are fine)

- [ ] **Step 3: Commit**

```bash
git add configuration.nix
git commit -m "feat: add Sunshine autoStart and uinput for remote input"
```

---

### Task 2: Shared Hypridle Suppress Directory (work-mode update)

**Files:**
- Modify: `modules/packages.nix:26-85` (work-mode script)

The existing `work-mode` script directly calls `systemctl --user stop/start hypridle.service`. Update it to use the shared suppress directory so it coordinates with the sunshine watcher.

- [ ] **Step 1: Update work-mode to use suppress directory**

In `modules/packages.nix`, replace the work-mode script (lines 26-85) with:

```nix
  work-mode = pkgs.writeShellScriptBin "work-mode" ''
    set -euo pipefail
    HC="${pkgs.hyprland}/bin/hyprctl"
    IC="${pkgs.inputmodule-control}/bin/inputmodule-control"
    BC="${pkgs.brightnessctl}/bin/brightnessctl"
    DEV="/dev/ttyACM0"
    INHIBIT_PID=""
    SUPPRESS_DIR="''${XDG_RUNTIME_DIR:-/tmp}/hypridle-suppress"
    SUPPRESS_FLAG="$SUPPRESS_DIR/work-mode"
    mkdir -p "$SUPPRESS_DIR"

    # suppress hypridle via shared flag
    touch "$SUPPRESS_FLAG"
    systemctl --user stop hypridle.service 2>/dev/null || true

    # save current keyboard backlight so we can restore it
    KBD_BRIGHTNESS=$("$BC" -d framework_laptop::kbd_backlight g 2>/dev/null || echo "")

    cleanup() {
      [ -n "$INHIBIT_PID" ] && kill "$INHIBIT_PID" 2>/dev/null && wait "$INHIBIT_PID" 2>/dev/null || true

      "$HC" keyword misc:mouse_move_enables_dpms false
      "$HC" keyword misc:key_press_enables_dpms false
      "$HC" dispatch dpms on

      # release suppress flag, only restart hypridle if no other suppressor is active
      rm -f "$SUPPRESS_FLAG"
      if [ -z "$(ls -A "$SUPPRESS_DIR" 2>/dev/null)" ]; then
        systemctl --user start hypridle.service 2>/dev/null || true
      fi

      # restore keyboard backlight
      [ -n "$KBD_BRIGHTNESS" ] && "$BC" -d framework_laptop::kbd_backlight s "$KBD_BRIGHTNESS" 2>/dev/null || true

      # wake the LED matrix
      [ -e "$DEV" ] && "$IC" --serial-dev "$DEV" led-matrix --sleeping false 2>/dev/null || true
    }
    trap cleanup EXIT

    # hold a sleep inhibitor in the background for the lifetime of this script
    ${pkgs.systemd}/bin/systemd-inhibit \
      --what=sleep:idle --who=work-mode --why="Work mode active" \
      --mode=block sleep infinity &
    INHIBIT_PID=$!

    # let input wake DPMS (hyprland defaults these to false)
    "$HC" keyword misc:mouse_move_enables_dpms true
    "$HC" keyword misc:key_press_enables_dpms true

    # turn off keyboard backlight
    "$BC" -d framework_laptop::kbd_backlight s 0 2>/dev/null || true

    # put the LED matrix to sleep
    [ -e "$DEV" ] && "$IC" --serial-dev "$DEV" led-matrix --sleeping true 2>/dev/null || true

    # turn screen off (no session lock, so Claude and remote-control keep working)
    "$HC" dispatch dpms off

    # poll until the user wakes the screen (any input turns DPMS back on)
    while true; do
      sleep 1
      if "$HC" monitors -j 2>/dev/null | grep -q '"dpmsStatus": true'; then
        break
      fi
    done

    # screen is back on, lock it now
    hyprlock-led
  '';
```

- [ ] **Step 2: Verify the config evaluates**

Run: `nix flake check --no-build 2>&1 | head -20`
Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add modules/packages.nix
git commit -m "refactor: use shared hypridle-suppress directory in work-mode"
```

---

### Task 3: Sunshine Session Watcher Service

**Files:**
- Modify: `modules/services.nix:1-275` (add script in `let` block, add service in body)

- [ ] **Step 1: Add the watcher script to the `let` block**

In `modules/services.nix`, add this after the `fingerprintWatchScript` definition (after line 211, before `micFixScript`):

```nix
  # Sunshine session watcher — suppresses hypridle and holds a sleep inhibitor
  # while a Moonlight client is connected. Tails the Sunshine journal for
  # CLIENT CONNECTED / CLIENT DISCONNECTED events.
  sunshineWatcherScript = pkgs.writeShellScript "sunshine-session-watcher" ''
    set -euo pipefail
    INHIBIT_PID=""
    SUPPRESS_DIR="''${XDG_RUNTIME_DIR:-/tmp}/hypridle-suppress"
    SUPPRESS_FLAG="$SUPPRESS_DIR/sunshine"
    mkdir -p "$SUPPRESS_DIR"

    suppress_idle() {
      [ -n "$INHIBIT_PID" ] && return
      touch "$SUPPRESS_FLAG"
      systemctl --user stop hypridle.service 2>/dev/null || true
      ${pkgs.systemd}/bin/systemd-inhibit --what=sleep --who=sunshine-watcher \
        --why="Sunshine client connected" --mode=block sleep infinity &
      INHIBIT_PID=$!
    }

    release_idle() {
      if [ -n "$INHIBIT_PID" ]; then
        kill "$INHIBIT_PID" 2>/dev/null || true
        wait "$INHIBIT_PID" 2>/dev/null || true
        INHIBIT_PID=""
      fi
      rm -f "$SUPPRESS_FLAG"
      if [ -z "$(ls -A "$SUPPRESS_DIR" 2>/dev/null)" ]; then
        systemctl --user start hypridle.service 2>/dev/null || true
      fi
    }

    trap 'release_idle; exit 0' EXIT INT TERM

    ${pkgs.systemd}/bin/journalctl --user -u sunshine -f -o cat --no-hostname | while IFS= read -r line; do
      case "$line" in
        *"CLIENT CONNECTED"*)
          suppress_idle
          ${ledmatrix-pkg}/bin/ledmatrix-notify bell &
          ;;
        *"CLIENT DISCONNECTED"*)
          release_idle
          ${ledmatrix-pkg}/bin/ledmatrix-notify bell &
          ;;
      esac
    done
  '';
```

- [ ] **Step 2: Add the ExecStopPost helper script**

Add this right after the `sunshineWatcherScript` definition:

```nix
  # Safety net: cleans up the suppress flag even after SIGKILL
  sunshineWatcherCleanup = pkgs.writeShellScript "sunshine-watcher-cleanup" ''
    SUPPRESS_DIR="''${XDG_RUNTIME_DIR:-/tmp}/hypridle-suppress"
    rm -f "$SUPPRESS_DIR/sunshine"
    if [ -z "$(ls -A "$SUPPRESS_DIR" 2>/dev/null)" ]; then
      systemctl --user start hypridle.service 2>/dev/null || true
    fi
  '';
```

- [ ] **Step 3: Add the systemd user service**

In the body of `modules/services.nix` (after the `ledmatrix-tailscale-watch` service block, before the ActivityWatch section, around line 470):

```nix
  # ─── Sunshine session watcher ───────────────────────────────────────────────
  systemd.user.services.sunshine-session-watcher = {
    Unit = {
      Description = "Suppress idle/sleep while Sunshine is streaming";
      After = [ "graphical-session.target" "sunshine.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${sunshineWatcherScript}";
      ExecStopPost = "${sunshineWatcherCleanup}";
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
```

- [ ] **Step 4: Verify the config evaluates**

Run: `nix flake check --no-build 2>&1 | head -20`
Expected: no errors

- [ ] **Step 5: Commit**

```bash
git add modules/services.nix
git commit -m "feat: add sunshine session watcher with idle/sleep inhibition"
```

---

### Task 4: Waybar Sunshine Module

**Files:**
- Modify: `modules/waybar.nix` (script in `let` block, module definition, modules-right x2, CSS x3)

- [ ] **Step 1: Add the Waybar status script**

In `modules/waybar.nix`, add this in the `let` block (after the existing script definitions, before `sharedModules`). Find the line that starts `sharedModules = {` and add before it:

```nix
  # Sunshine remote streaming status for Waybar
  sunshineWaybarScript = pkgs.writeShellScript "waybar-sunshine" ''
    # hide module entirely if sunshine isn't running
    systemctl --user is-active sunshine.service >/dev/null 2>&1 || exit 0

    LAST=$(${pkgs.systemd}/bin/journalctl --user -u sunshine --no-pager -o cat -n 200 2>/dev/null \
      | grep -E "CLIENT (CONNECTED|DISCONNECTED)" | tail -1 || true)

    if echo "$LAST" | grep -q "CLIENT CONNECTED"; then
      printf '{"text":"󰢹","tooltip":"Sunshine: streaming","class":"streaming"}\n'
    else
      printf '{"text":"󰢹","tooltip":"Sunshine: idle","class":"idle"}\n'
    fi
  '';
```

- [ ] **Step 2: Add the module definition**

In the `sharedModules` block, add after `"custom/tailscale"` (after line 435):

```nix
        "custom/sunshine" = {
          interval = 5;
          return-type = "json";
          exec = "${sunshineWaybarScript}";
          format = "{}";
          on-click = "xdg-open https://localhost:47990";
          tooltip = true;
        };
```

- [ ] **Step 3: Add to laptop modules-right**

In the `sharedLayout` `modules-right` array (line 500-519), add `"custom/sunshine"` between `"custom/tailscale"` and `"bluetooth"`:

```nix
          "custom/tailscale"
          "custom/sunshine"
          "bluetooth"
```

- [ ] **Step 4: Add to external monitor modules-right**

In the external monitor override `modules-right` array (line 543-561), add `"custom/sunshine"` between `"custom/tailscale"` and `"bluetooth"`:

```nix
              "custom/tailscale"
              "custom/sunshine"
              "bluetooth"
```

- [ ] **Step 5: Add to shared right-module padding CSS**

In the shared padding selector (lines 654-672), add `#custom-sunshine,` before the closing `#custom-power {`:

```css
        #custom-notification,
        #custom-sunshine,
        #tray,
        #custom-power {
```

- [ ] **Step 6: Add Sunshine accent colour CSS**

After the `#custom-tailscale.disconnected` rule (line 718), add:

```css
        #custom-sunshine              { color: #bd93f9; }
        #custom-sunshine.idle         { color: #6272a4; }
```

- [ ] **Step 7: Add to external monitor compact padding CSS**

In the external monitor padding override (lines 794-812), add `window#waybar:not(.eDP-1) #custom-sunshine,` after the `#custom-tailscale` line:

```css
        window#waybar:not(.eDP-1) #custom-tailscale,
        window#waybar:not(.eDP-1) #custom-sunshine,
        window#waybar:not(.eDP-1) #custom-notification,
```

- [ ] **Step 8: Verify the config evaluates**

Run: `nix flake check --no-build 2>&1 | head -20`
Expected: no errors

- [ ] **Step 9: Commit**

```bash
git add modules/waybar.nix
git commit -m "feat: add Waybar sunshine streaming status module"
```

---

### Task 5: Walker Tools Menu Entry

**Files:**
- Modify: `modules/hyprland.nix:548-566` (tools.toml)

- [ ] **Step 1: Add Sunshine entry to tools.toml**

In `modules/hyprland.nix`, in the tools.toml string, add a new entry before the LED Matrix entry (before line 562):

```toml
    [[entries]]
    text = "Sunshine"
    keywords = ["sunshine", "remote", "stream", "moonlight"]
    actions = { run = "xdg-open https://localhost:47990" }
```

- [ ] **Step 2: Verify the config evaluates**

Run: `nix flake check --no-build 2>&1 | head -20`
Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add modules/hyprland.nix
git commit -m "feat: add Sunshine to Walker tools menu"
```

---

### Task 6: Build and Verify

**Files:** none (verification only)

- [ ] **Step 1: Build the full NixOS configuration**

Run: `nix build .#nixosConfigurations.$(hostname).config.system.build.toplevel --no-link 2>&1 | tail -20`
Expected: build succeeds with no errors

- [ ] **Step 2: Review all changes**

Run: `git diff HEAD~5 --stat` to confirm the 4 changed files match the plan:
- `configuration.nix`
- `modules/packages.nix`
- `modules/services.nix`
- `modules/waybar.nix`
- `modules/hyprland.nix`

- [ ] **Step 3: Post-deploy setup notes**

After applying with `setup.sh`:
1. Open `https://localhost:47990` in zen-browser (accept the self-signed cert warning)
2. Create a Sunshine username and password
3. Install Moonlight on the Windows machine
4. In Moonlight, add the laptop's IP (local or Tailscale) as a new computer
5. Enter the pairing PIN shown in Sunshine's web UI
6. Connect and verify the Hyprland desktop streams correctly
