# Sunshine Integration Design

Integrate Sunshine (remote desktop streaming) into the NixOS/Hyprland setup so the laptop can be controlled from a Windows machine on the same network via Moonlight, with proper idle handling, status visibility, and LED feedback.

## Context

- Same network, different desk/room. The laptop screen stays active.
- Sunshine streams the real Hyprland session as-is (no virtual display).
- Moonlight on Windows is the client.
- Tailscale is available for connecting via tailnet IP if preferred.

## 1. Sunshine NixOS Configuration

In `configuration.nix`:

```nix
services.sunshine = {
  enable = true;
  autoStart = true;
  capSysAdmin = true;
  openFirewall = true;
};

# uinput device needed for Sunshine's virtual keyboard/mouse/gamepad input
hardware.uinput.enable = true;
```

No `applications` or `settings` blocks. Sunshine streams the full desktop by default, and leaving these unset keeps the web UI fully configurable for pairing, settings tweaks, and app management.

The user is already in the `input` group (`configuration.nix` line 194), which is required for `/dev/uinput` access.

Sunshine runs as a **systemd user service** (`systemd.user.services.sunshine`) bound to `graphical-session.target`. It auto-starts with the Hyprland session. Capture method auto-detects to `wlr` (wlroots screencopy) on Hyprland. Encoder, audio sink (PipeWire), and other settings auto-detect correctly and can be tuned via the web UI if needed.

## 2. Idle/Sleep Inhibitor While Streaming

**Problem**: Hypridle dims the screen at 5 min, locks at 10 min, turns off DPMS at 15 min, and suspends at 30 min. All of these break a remote session.

**How idle inhibition works in this setup**: Hypridle uses the Wayland `ext-idle-notify-v1` protocol, not systemd's idle inhibitor. A `systemd-inhibit --what=idle` lock has no effect on hypridle. However, `--what=sleep` does block `systemctl suspend-then-hibernate` (the 30 min timeout). To prevent dim/lock/DPMS-off, we need to stop hypridle entirely while streaming.

**Coordination with work-mode**: The existing `work-mode` script (`modules/packages.nix`) also stops/starts hypridle. To avoid conflicts where one manager restarts hypridle while the other still needs it suppressed, both use a shared suppress directory at `$XDG_RUNTIME_DIR/hypridle-suppress/`. Each creates a named flag file on suppress and removes it on release. Hypridle only restarts when the directory is empty.

**Solution**: A systemd user service that tails the Sunshine user journal for `CLIENT CONNECTED` / `CLIENT DISCONNECTED` log lines. On connect, it suppresses hypridle and holds a sleep inhibitor. On disconnect, it releases the suppression and the inhibitor.

In `modules/services.nix`, add a new script + service:

```bash
sunshineWatcherScript = pkgs.writeShellScript "sunshine-session-watcher" '
  set -euo pipefail
  INHIBIT_PID=""
  SUPPRESS_DIR="${XDG_RUNTIME_DIR:-/tmp}/hypridle-suppress"
  SUPPRESS_FLAG="$SUPPRESS_DIR/sunshine"
  mkdir -p "$SUPPRESS_DIR"

  suppress_idle() {
    [ -n "$INHIBIT_PID" ] && return
    touch "$SUPPRESS_FLAG"
    systemctl --user stop hypridle.service 2>/dev/null || true
    systemd-inhibit --what=sleep --who=sunshine-watcher \
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
    # only restart hypridle if no other suppressor is active
    if [ -z "$(ls -A "$SUPPRESS_DIR" 2>/dev/null)" ]; then
      systemctl --user start hypridle.service 2>/dev/null || true
    fi
  }

  trap "release_idle; exit 0" EXIT INT TERM

  journalctl --user -u sunshine -f -o cat --no-hostname | while IFS= read -r line; do
    case "$line" in
      *"CLIENT CONNECTED"*)
        suppress_idle
        ledmatrix-notify bell &
        ;;
      *"CLIENT DISCONNECTED"*)
        release_idle
        ledmatrix-notify bell &
        ;;
    esac
  done
'
```

Service unit:
```nix
systemd.user.services.sunshine-session-watcher = {
  Unit = {
    Description = "Suppress idle/sleep while Sunshine is streaming";
    After = [ "graphical-session.target" "sunshine.service" ];
    PartOf = [ "graphical-session.target" ];
  };
  Service = {
    Type = "simple";
    ExecStart = "${sunshineWatcherScript}";
    # safety net: if the process is killed without trap firing, restart hypridle
    ExecStopPost = "bash -c 'rm -f \${XDG_RUNTIME_DIR:-/tmp}/hypridle-suppress/sunshine; [ -z \"$(ls -A \${XDG_RUNTIME_DIR:-/tmp}/hypridle-suppress 2>/dev/null)\" ] && systemctl --user start hypridle.service 2>/dev/null || true'";
    Restart = "always";
    RestartSec = "5s";
  };
  Install.WantedBy = [ "graphical-session.target" ];
};
```

Key details:
- `journalctl --user -u sunshine` (user scope) because the NixOS Sunshine module creates a user service.
- `--what=sleep` only (not `idle`), matching the existing `performance-sleep-inhibitor` pattern.
- Hypridle is stopped/started to prevent dim, lock, and DPMS-off during streaming.
- `release_idle` always removes the flag and conditionally restarts hypridle, even if `INHIBIT_PID` is empty (handles watcher-restart-mid-session case).
- `ExecStopPost` ensures hypridle is restored even after SIGKILL (OOM, systemd timeout).
- `Restart=always` + trap handles normal cleanup. If `journalctl -f` loses the stream (sunshine stops), the pipe breaks, the script exits, the trap fires.

**Edge case**: If the client crashes without a clean disconnect, `CLIENT DISCONNECTED` may not appear in the log. Hypridle stays stopped until the service restarts (when sunshine restarts or the pipe breaks). Worst case, manual `systemctl --user restart sunshine-session-watcher` clears it. This matches the known Sunshine limitation.

**work-mode changes**: Update the existing `work-mode` script to use the same suppress directory pattern instead of direct stop/start. Create `$XDG_RUNTIME_DIR/hypridle-suppress/work-mode` on activate, remove on cleanup, only start hypridle when the directory is empty.

## 3. Waybar Module

A `custom/sunshine` module in the right section, placed between `custom/tailscale` and `bluetooth` (network-adjacent, logically grouped).

**Script** (as `pkgs.writeShellScript`, matching the `powerDrawScript`/`timetrackScript` pattern):

Checks if sunshine is active, then greps the recent journal for the last connection event.

- Connected: `{"text": "󰢹", "tooltip": "Sunshine: streaming", "class": "streaming"}`
- Not connected: `{"text": "󰢹", "tooltip": "Sunshine: idle", "class": "idle"}`
- Service not running: bare `exit 0` with no output (hides the module entirely)

The "no output = hidden module" pattern matches `ledmatrixStatusScript` (`[ ! -e "$DEV" ] && exit 0`).

**Waybar script logic**:
```bash
# exit silently if sunshine isn't running (hides module)
systemctl --user is-active sunshine.service >/dev/null 2>&1 || exit 0

# check last connection event in the journal
LAST=$(journalctl --user -u sunshine --no-pager -o cat -n 200 2>/dev/null \
  | grep -E "CLIENT (CONNECTED|DISCONNECTED)" | tail -1 || true)

if echo "$LAST" | grep -q "CLIENT CONNECTED"; then
  printf '{"text":"󰢹","tooltip":"Sunshine: streaming","class":"streaming"}\n'
else
  printf '{"text":"󰢹","tooltip":"Sunshine: idle","class":"idle"}\n'
fi
```

**Module config**:
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

Polling every 5s matches `custom/tailscale`. `xdg-open` is consistent with `custom/timetrack` (respects default browser = zen-browser).

**CSS** (three locations):
- Add `#custom-sunshine` to the shared right-module padding selector (lines 655-672): `padding: 0 10px`
- Add class rules after `#custom-tailscale`: `.streaming { color: #bd93f9; }`, `.idle { color: #6272a4; }`
- Add to the external monitor compact padding override (lines 794-813): `padding: 0 8px`

**Insertion points** (two `modules-right` arrays):
- Laptop (eDP-1): between `custom/tailscale` (line 513) and `bluetooth` (line 514)
- External monitors: between `custom/tailscale` (line 555) and `bluetooth` (line 556)

## 4. LED Matrix Feedback

Reuse the existing `ledmatrix-notify bell` command for both connect and disconnect events. The `bell` style is the closest semantic match for a connection notification.

This is handled inside the same journal-tailing service from section 2 (no separate watcher needed). See the script above.

No changes to `notify.py` needed. Custom `link`/`unlink` pixel art icons would be nice but aren't worth the complexity for v1. Can revisit later if the `bell` animation feels too generic.

## 5. Walker Tools Menu Entry

Add a Sunshine entry to the existing tools menu (`modules/hyprland.nix`, tools.toml):

```toml
[[entries]]
text = "Sunshine"
keywords = ["sunshine", "remote", "stream", "moonlight"]
actions = { run = "xdg-open https://localhost:47990" }
```

Opens the Sunshine web UI for pairing clients, checking status, and adjusting settings. Only useful when the Sunshine service is running (browser shows an error page otherwise, which is expected).

## Files Changed

| File | Change |
|---|---|
| `configuration.nix` | Add `autoStart`, `hardware.uinput.enable`. No `applications` block. |
| `modules/services.nix` | Add sunshine session watcher script + systemd service |
| `modules/packages.nix` | Update `work-mode` to use shared hypridle-suppress directory |
| `modules/waybar.nix` | Add `custom/sunshine` module, script, CSS (3 locations), modules-right (2 locations) |
| `modules/hyprland.nix` | Add Sunshine entry to tools.toml |

## What We're NOT Doing

- No virtual display or resolution switching (streaming the real desktop)
- No `applications` or `settings` blocks (keep web UI fully configurable)
- No custom LED pixel art (reuse existing `bell` animation)
- No second journal tailer (LED + inhibitor + hypridle control share one service)
- No prep-cmd approach (journal tailing is more robust for disconnect detection)
