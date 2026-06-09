{ pkgs, user, ... }:

let
  ledmatrix-pkg = pkgs.python3.pkgs.buildPythonApplication {
    pname = "ledmatrix";
    version = "0.1.0";
    src = ../scripts/ledmatrix;
    format = "pyproject";
    nativeBuildInputs = [ pkgs.python3.pkgs.setuptools ];
    doCheck = false;
  };

  # AC plug/unplug notification daemon
  acMonitorScript = pkgs.writeShellScript "ac-monitor" ''
    LAST_STATE=""
    ${pkgs.upower}/bin/upower --monitor | while IFS= read -r line; do
      if echo "$line" | grep -q "line_power"; then
        sleep 0.5
        AC_PATH=$(grep -rl "Mains" /sys/class/power_supply/*/type 2>/dev/null | head -1 | xargs -I{} dirname {})
        ONLINE=$(cat "$AC_PATH/online" 2>/dev/null || echo "?")
        if [ "$ONLINE" = "1" ] && [ "$LAST_STATE" != "1" ]; then
          LAST_STATE="1"
          ${pkgs.libnotify}/bin/notify-send -u low -t 3000 "󰚥 AC Connected" "Plugged in"
          ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance
          ${ledmatrix-pkg}/bin/ledmatrix-charging plug &
        elif [ "$ONLINE" = "0" ] && [ "$LAST_STATE" != "0" ]; then
          LAST_STATE="0"
          ${pkgs.libnotify}/bin/notify-send -u low -t 3000 "󰁾 AC Disconnected" "Running on battery"
          ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver
          ${ledmatrix-pkg}/bin/ledmatrix-charging unplug &
        fi
      fi
    done
  '';

  # Low battery warning + auto-hibernate at 5%
  batteryMonitorScript = pkgs.writeShellScript "battery-monitor" ''
    BAT=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
    [ -z "$BAT" ] && exit 0
    CAPACITY=$(cat "$BAT/capacity" 2>/dev/null || echo 100)
    STATUS=$(cat "$BAT/status" 2>/dev/null || echo "Unknown")
    STATE_FILE="''${XDG_RUNTIME_DIR:-/tmp}/battery-notified"

    [ "$STATUS" != "Discharging" ] && { rm -f "$STATE_FILE"; exit 0; }

    LAST=$(cat "$STATE_FILE" 2>/dev/null || echo 100)

    if   [ "$CAPACITY" -le 5  ] && [ "$LAST" -gt 5  ]; then
      ${pkgs.libnotify}/bin/notify-send -u critical -t 0 "󰁺 Battery Critical" "At ''${CAPACITY}% — hibernating in 30s"
      ${ledmatrix-pkg}/bin/ledmatrix-battery --battery "$CAPACITY" &
      LED_PID=$!
      echo 5 > "$STATE_FILE"
      sleep 30
      kill "$LED_PID" 2>/dev/null
      systemctl hibernate
    elif [ "$CAPACITY" -le 10 ] && [ "$LAST" -gt 10 ]; then
      ${pkgs.libnotify}/bin/notify-send -u critical -t 0 "󰁻 Battery Low" "At ''${CAPACITY}% — please plug in"
      ${ledmatrix-pkg}/bin/ledmatrix-battery --battery "$CAPACITY" &
      echo 10 > "$STATE_FILE"
    elif [ "$CAPACITY" -le 20 ] && [ "$LAST" -gt 20 ]; then
      ${pkgs.libnotify}/bin/notify-send -u normal -t 8000 "󰁼 Battery Warning" "At ''${CAPACITY}%"
      ${ledmatrix-pkg}/bin/ledmatrix-battery --battery "$CAPACITY" &
      echo 20 > "$STATE_FILE"
    fi
  '';

  # Volume watcher — calls ledmatrix-bar on sink volume changes
  volumeWatchScript = pkgs.writeShellScript "ledmatrix-volume-watch" ''
    set -euo pipefail
    _vol() {
      ${pkgs.pulseaudio}/bin/pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null \
        | grep -oP '\d+(?=%)' | head -1 || echo "0"
    }
    PREV_PCT=$(_vol)
    ${pkgs.pulseaudio}/bin/pactl subscribe 2>/dev/null | while IFS= read -r event; do
      if echo "$event" | grep -q "sink"; then
        PCT=$(_vol)
        if [ "$PCT" != "$PREV_PCT" ]; then
          ${ledmatrix-pkg}/bin/ledmatrix-bar "$PCT" &
          PREV_PCT="$PCT"
        fi
      fi
    done
  '';

  # Brightness watcher — calls ledmatrix-bar on backlight changes
  brightnessWatchScript = pkgs.writeShellScript "ledmatrix-brightness-watch" ''
    set -euo pipefail
    LOCK="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-monitor-lock"
    _pct() {
      CUR=$(${pkgs.brightnessctl}/bin/brightnessctl g 2>/dev/null || echo 0)
      MAX=$(${pkgs.brightnessctl}/bin/brightnessctl m 2>/dev/null || echo 1)
      echo $(( CUR * 100 / MAX ))
    }
    PREV_PCT=$(_pct)
    ${pkgs.systemd}/bin/udevadm monitor --udev --subsystem-match=backlight 2>/dev/null | \
    while IFS= read -r _line; do
      sleep 0.05
      PCT=$(_pct)
      if [ "$PCT" != "$PREV_PCT" ]; then
        PREV_PCT="$PCT"
        [ ! -f "$LOCK" ] && ${ledmatrix-pkg}/bin/ledmatrix-bar "$PCT" &
      fi
    done
  '';

  # Hyprland IPC monitor watcher — triggers ledmatrix-monitor on connect/disconnect
  monitorWatchScript = pkgs.writeShellScript "ledmatrix-monitor-watch" ''
    set -euo pipefail
    LOCK="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-monitor-lock"
    SOCK=$(ls /run/user/*/hypr/*/.socket2.sock 2>/dev/null | head -1)
    [ -z "$SOCK" ] && exit 1
    ${pkgs.socat}/bin/socat -u "UNIX-CONNECT:$SOCK" - | while IFS= read -r event; do
      case "$event" in
        monitoraddedv2*)
          touch "$LOCK"
          ${ledmatrix-pkg}/bin/ledmatrix-monitor connect &
          (sleep 6; rm -f "$LOCK") &
          ;;
        monitorremoved*)
          touch "$LOCK"
          ${ledmatrix-pkg}/bin/ledmatrix-monitor disconnect &
          (sleep 6; rm -f "$LOCK") &
          ;;
      esac
    done
  '';

  # WiFi up/down watcher — monitors nmcli for connection changes
  wifiWatchScript = pkgs.writeShellScript "ledmatrix-wifi-watch" ''
    set -euo pipefail
    _wifi_state() {
      STATE=$(${pkgs.networkmanager}/bin/nmcli -t -f STATE general 2>/dev/null | head -1 || echo "unknown")
      [ "$STATE" = "connected" ] && echo "up" || echo "down"
    }
    PREV=$(_wifi_state)
    sleep 5
    while true; do
      CUR=$(_wifi_state)
      if [ "$CUR" != "$PREV" ]; then
        ${ledmatrix-pkg}/bin/ledmatrix-network "$CUR" --mode wifi &
        PREV="$CUR"
      fi
      sleep 5
    done
  '';

  # Tailscale up/down watcher — polls every 5s for state changes
  tailscaleWatchScript = pkgs.writeShellScript "ledmatrix-tailscale-watch" ''
    set -euo pipefail
    _ts_state() {
      if ${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null \
          | ${pkgs.jq}/bin/jq -e '.BackendState == "Running"' > /dev/null 2>&1; then
        echo "up"
      else
        echo "down"
      fi
    }
    PREV=$(_ts_state)
    sleep 5
    while true; do
      STATE=$(_ts_state)
      if [ "$STATE" != "$PREV" ]; then
        ${ledmatrix-pkg}/bin/ledmatrix-network "$STATE" --mode vpn &
        PREV="$STATE"
      fi
      sleep 5
    done
  '';

  # USB plug/unplug watcher — triggers LED animation for peripheral devices.
  # Filters out Framework internal USB (vendor 32ac) and non-device events.
  usbWatchScript = pkgs.writeShellScript "ledmatrix-usb-watch" ''
    set -euo pipefail
    LOCK="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-monitor-lock"
    pa=""
    pd=""
    pv=""
    ph=""
    ${pkgs.systemd}/bin/udevadm monitor --udev --subsystem-match=usb --property 2>/dev/null | \
    while IFS= read -r line; do
      case "$line" in
        Monitor*)           ;;
        UDEV*)              pa=""; pd=""; pv=""; ph="" ;;
        ACTION=add)         pa=plug ;;
        ACTION=remove)      pa=unplug ;;
        DEVTYPE=usb_device) pd=usb_device ;;
        ID_VENDOR_ID=32ac)  pv=skip ;;
        ID_USB_CLASS=09)    ph=skip ;;
        "")
          if [ "$pd" = "usb_device" ] && [ -z "$pv" ] && [ -z "$ph" ] && [ -n "$pa" ]; then
            (sleep 1; [ ! -f "$LOCK" ] && ${ledmatrix-pkg}/bin/ledmatrix-usb "$pa") &
          fi
          ;;
      esac
    done
  '';

  # Fingerprint watcher — listens for fprintd VerifyStatus signals on the system bus.
  fingerprintWatchScript = pkgs.writeShellScript "ledmatrix-fingerprint-watch" ''
    set -euo pipefail
    ${pkgs.glib}/bin/gdbus monitor --system --dest net.reactivated.Fprint 2>/dev/null | \
    while IFS= read -r line; do
      if echo "$line" | grep -q "VerifyStatus.*verify-match"; then
        # Skip LED animation when hyprlock is active (unlock animation handles it)
        pidof hyprlock >/dev/null 2>&1 || ${ledmatrix-pkg}/bin/ledmatrix-fingerprint success &
      elif echo "$line" | grep -q "VerifyStatus"; then
        ${ledmatrix-pkg}/bin/ledmatrix-fingerprint failure &
      fi
    done
  '';

  # Sunshine session watcher: suppresses hypridle and holds a sleep inhibitor
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

    # recover state if restarting mid-session
    LAST=$(${pkgs.systemd}/bin/journalctl --user -u sunshine --no-pager -o cat -n 200 2>/dev/null \
      | grep -E "CLIENT (CONNECTED|DISCONNECTED)" | tail -1 || true)
    case "$LAST" in *"CLIENT CONNECTED"*) suppress_idle ;; esac

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

  # Safety net: cleans up the suppress flag even after SIGKILL
  sunshineWatcherCleanup = pkgs.writeShellScript "sunshine-watcher-cleanup" ''
    SUPPRESS_DIR="''${XDG_RUNTIME_DIR:-/tmp}/hypridle-suppress"
    rm -f "$SUPPRESS_DIR/sunshine"
    if [ -z "$(ls -A "$SUPPRESS_DIR" 2>/dev/null)" ]; then
      systemctl --user start hypridle.service 2>/dev/null || true
    fi
  '';

  # ALC295 mic fix — tames the +30 dB defaults that cause clipping.
  # Runs after WirePlumber so it doesn't get overridden by state restoration.
  micFixScript = pkgs.writeShellScript "mic-fix-alc295" ''
    # wait for WirePlumber to finish restoring state
    sleep 2

    for codec in /proc/asound/card*/codec#*; do
      if grep -q "ALC295" "$codec" 2>/dev/null; then
        CARD=$(echo "$codec" | grep -oP 'card\K[0-9]+')
        ${pkgs.alsa-utils}/bin/amixer -c "$CARD" sset 'Mic Boost' 1
        ${pkgs.alsa-utils}/bin/amixer -c "$CARD" sset 'Capture' 25
        ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SOURCE@ 0.40
        break
      fi
    done
  '';

  # Sleep inhibitor for performance profile. Holds a systemd sleep inhibitor
  # whenever the active power profile is "performance", blocking suspend from
  # both logind (lid close) and hypridle. Watches D-Bus for profile changes.
  sleepInhibitorScript = pkgs.writeShellScript "performance-sleep-inhibitor" ''
    set -euo pipefail
    INHIBIT_PID=""

    start_inhibit() {
      if [ -z "$INHIBIT_PID" ]; then
        ${pkgs.systemd}/bin/systemd-inhibit --what=sleep --who="power-profile" \
          --why="Performance profile active" --mode=block sleep infinity &
        INHIBIT_PID=$!
      fi
    }

    stop_inhibit() {
      if [ -n "$INHIBIT_PID" ]; then
        kill "$INHIBIT_PID" 2>/dev/null || true
        wait "$INHIBIT_PID" 2>/dev/null || true
        INHIBIT_PID=""
      fi
    }

    trap 'stop_inhibit; exit 0' EXIT INT TERM

    # set initial state
    PROFILE=$(${pkgs.power-profiles-daemon}/bin/powerprofilesctl get 2>/dev/null || echo "")
    [ "$PROFILE" = "performance" ] && start_inhibit

    # watch for profile changes via D-Bus
    ${pkgs.glib}/bin/gdbus monitor --system \
      --dest net.hadess.PowerProfiles \
      --object-path /net/hadess/PowerProfiles 2>/dev/null | \
    while IFS= read -r line; do
      if echo "$line" | grep -q "ActiveProfile"; then
        PROFILE=$(${pkgs.power-profiles-daemon}/bin/powerprofilesctl get 2>/dev/null || echo "")
        if [ "$PROFILE" = "performance" ]; then
          start_inhibit
        else
          stop_inhibit
        fi
      fi
    done
  '';

in
{
  # Unlocks the GNOME keyring at session start using an empty password.
  # greetd does passwordless auto-login so pam_gnome_keyring never gets a token
  # and the keyring stays locked. Requires the keyring password to be empty
  # (set it once via seahorse: Passwords > Login > Change Password > leave blank).
  systemd.user.services.gnome-keyring-unlock = {
    Unit = {
      Description = "Auto-unlock GNOME keyring at login";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      # GNOME_KEYRING_CONTROL points to the daemon socket; %t expands to $XDG_RUNTIME_DIR.
      # printf "\n" sends an empty password (just a newline terminator).
      Environment = "GNOME_KEYRING_CONTROL=%t/keyring";
      ExecStart = "${pkgs.writeShellScript "unlock-keyring" ''
        printf "\n" | ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --unlock
      ''}";
      PassEnvironment = "DBUS_SESSION_BUS_ADDRESS";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # ─── ALC295 mic fix (runs after WirePlumber to survive state restoration) ────
  systemd.user.services.mic-fix-alc295 = {
    Unit = {
      Description = "Fix ALC295 mic clipping (tame boost + capture)";
      After = [ "wireplumber.service" ];
      Requires = [ "wireplumber.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${micFixScript}";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # ─── Battery & power monitoring services ─────────────────────────────────────
  systemd.user.services.ac-monitor = {
    Unit = {
      Description = "AC plug/unplug notifications";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${acMonitorScript}";
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.performance-sleep-inhibitor = {
    Unit = {
      Description = "Hold sleep inhibitor while performance profile is active";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${sleepInhibitorScript}";
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.battery-monitor = {
    Unit = {
      Description = "Low battery warnings and auto-hibernate";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${batteryMonitorScript}";
    };
  };

  systemd.user.timers.battery-monitor = {
    Unit.Description = "Battery monitor — runs every minute";
    Timer = {
      OnCalendar = "*:0/1";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };


  # ─── LED matrix event watchers ────────────────────────────────────────────────
  systemd.user.services.ledmatrix-volume-watch = {
    Unit = {
      Description = "LED matrix volume animation watcher";
      After = [ "graphical-session.target" "pipewire-pulse.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${volumeWatchScript}";
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.ledmatrix-brightness-watch = {
    Unit = {
      Description = "LED matrix brightness animation watcher";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${brightnessWatchScript}";
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.ledmatrix-monitor-watch = {
    Unit = {
      Description = "LED matrix monitor connect/disconnect animation watcher";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${monitorWatchScript}";
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.ledmatrix-wifi-watch = {
    Unit = {
      Description = "LED matrix wifi up/down animation watcher";
      After = [ "graphical-session.target" "network.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${wifiWatchScript}";
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.ledmatrix-usb-watch = {
    Unit = {
      Description = "LED matrix USB plug/unplug animation watcher";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${usbWatchScript}";
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.ledmatrix-fingerprint-watch = {
    Unit = {
      Description = "LED matrix fingerprint scan result animation watcher";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${fingerprintWatchScript}";
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.ledmatrix-tailscale-watch = {
    Unit = {
      Description = "LED matrix tailscale up/down animation watcher";
      After = [ "graphical-session.target" "network-online.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${tailscaleWatchScript}";
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Sunshine session watcher: suppress idle/sleep while streaming
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

  # ─── ActivityWatch — time tracking ────────────────────────────────────────────
  systemd.user.services.aw-server = {
    Unit = {
      Description = "ActivityWatch server (Rust)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.aw-server-rust}/bin/aw-server";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.aw-awatcher = {
    Unit = {
      Description = "ActivityWatch Wayland watcher (window + idle)";
      After = [ "graphical-session.target" "aw-server.service" ];
      Requires = [ "aw-server.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.awatcher}/bin/awatcher";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
