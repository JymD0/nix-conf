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
      systemctl hibernate --check-inhibitors=no
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

  # Clipboard bridge for an active Sunshine session. Deliberately not a
  # WantedBy=graphical-session service: the watcher below starts it on
  # CLIENT CONNECTED and stops it on CLIENT DISCONNECTED, so the port only
  # exists while someone is actually streaming.
  clipboardBridgeScript = pkgs.writeScript "sunshine-clipboard-bridge" ''
    #!${pkgs.python3}/bin/python3
    # Left out of allowedTCPPorts on purpose. That leaves it reachable over
    # tailscale0 (a trusted interface) but blocked from the LAN, and a shared
    # token is still required so a stray tailnet device cannot read along.
    import hmac
    import http.server
    import os
    import secrets
    import subprocess

    PORT = 48020
    MAX_BODY = 1 << 20
    WL_COPY = "${pkgs.wl-clipboard}/bin/wl-copy"
    WL_PASTE = "${pkgs.wl-clipboard}/bin/wl-paste"


    def load_token():
        base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
        state = os.path.join(base, "sunshine-clipboard")
        os.makedirs(state, mode=0o700, exist_ok=True)
        path = os.path.join(state, "token")
        if not os.path.exists(path):
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w") as handle:
                handle.write(secrets.token_urlsafe(32))
        with open(path) as handle:
            return handle.read().strip()


    TOKEN = load_token()


    class Handler(http.server.BaseHTTPRequestHandler):
        server_version = "sunshine-clipboard"

        def allowed(self):
            if self.path != "/clip":
                return False
            got = self.headers.get("X-Token", "")
            try:
                return hmac.compare_digest(got.encode("ascii"), TOKEN.encode("ascii"))
            except UnicodeError:
                return False

        def do_GET(self):
            if not self.allowed():
                self.send_error(403)
                return
            body = subprocess.run([WL_PASTE, "-n"], capture_output=True).stdout
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            if not self.allowed():
                self.send_error(403)
                return
            size = int(self.headers.get("Content-Length") or 0)
            if size < 1 or size > MAX_BODY:
                self.send_error(413)
                return
            subprocess.run([WL_COPY], input=self.rfile.read(size))
            self.send_response(204)
            self.end_headers()

        def log_message(self, fmt, *args):
            pass


    http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
  '';

  # Sunshine session watcher: suppresses hypridle and holds a sleep inhibitor
  # while a Moonlight client is connected. Tails the Sunshine journal for
  # CLIENT CONNECTED / CLIENT DISCONNECTED events. Also inhibits lid-switch
  # handling, since logind ignores plain sleep inhibitors for lid actions and
  # would suspend mid-stream on battery.
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
      ${pkgs.systemd}/bin/systemd-inhibit --what=sleep:handle-lid-switch --who=sunshine-watcher \
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

    clipboard_on() { systemctl --user start sunshine-clipboard.service 2>/dev/null || true; }
    clipboard_off() { systemctl --user stop sunshine-clipboard.service 2>/dev/null || true; }

    trap 'release_idle; clipboard_off; exit 0' EXIT INT TERM

    # recover state if restarting mid-session
    LAST=$(${pkgs.systemd}/bin/journalctl --user -u sunshine --no-pager -o cat -b -n 200 2>/dev/null \
      | grep -E "CLIENT (CONNECTED|DISCONNECTED)" | tail -1 || true)
    case "$LAST" in *"CLIENT CONNECTED"*) suppress_idle; clipboard_on ;; esac

    ${pkgs.systemd}/bin/journalctl --user -u sunshine -f -o cat --no-hostname | while IFS= read -r line; do
      case "$line" in
        *"CLIENT CONNECTED"*)
          suppress_idle
          clipboard_on
          ${ledmatrix-pkg}/bin/ledmatrix-notify bell &
          ;;
        *"CLIENT DISCONNECTED"*)
          release_idle
          clipboard_off
          ${ledmatrix-pkg}/bin/ledmatrix-notify bell &
          ;;
      esac
    done
  '';

  # Safety net: cleans up the suppress flag even after SIGKILL
  sunshineWatcherCleanup = pkgs.writeShellScript "sunshine-watcher-cleanup" ''
    systemctl --user stop sunshine-clipboard.service 2>/dev/null || true
    SUPPRESS_DIR="''${XDG_RUNTIME_DIR:-/tmp}/hypridle-suppress"
    rm -f "$SUPPRESS_DIR/sunshine"
    if [ -z "$(ls -A "$SUPPRESS_DIR" 2>/dev/null)" ]; then
      systemctl --user start hypridle.service 2>/dev/null || true
    fi
  '';

  # ALC295 mic setup. WirePlumber drives the ALSA capture control itself, so
  # poking it with amixer here just gets overwritten a moment later. Go through
  # wpctl instead. The unmute matters most: a stray mic-mute keypress sticks
  # across reboots once WirePlumber saves it, and apps then see a dead device.
  micFixScript = pkgs.writeShellScript "mic-fix-alc295" ''
    set -euo pipefail

    # wait for WirePlumber to finish restoring state
    sleep 2

    ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_SOURCE@ 0

    # only force the level for the built-in mic, leave headsets where they are
    SOURCE_INFO=$(${pkgs.wireplumber}/bin/wpctl inspect @DEFAULT_SOURCE@)
    case "$SOURCE_INFO" in
      *ALC295*) ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SOURCE@ 0.27 ;;
    esac
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

  # aw-server can wedge without exiting: a disk-full panic poisons its datastore
  # lock and every request 504s forever while systemd still sees the process as
  # running. Probe the buckets endpoint and restart the pair when it stops
  # answering with real data.
  awWatchdogScript = pkgs.writeShellScript "aw-watchdog" ''
    set -euo pipefail
    # leave it alone if the user stopped it on purpose
    systemctl --user is-active --quiet aw-server.service || exit 0
    if ${pkgs.curl}/bin/curl -sf -m 10 http://localhost:5600/api/0/buckets \
        | ${pkgs.jq}/bin/jq -e 'type == "object"' > /dev/null; then
      exit 0
    fi
    echo "aw-server not returning bucket data, restarting"
    systemctl --user restart aw-server.service aw-awatcher.service
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
      Description = "Unmute and level the ALC295 mic";
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

  # Clipboard bridge, started and stopped by the session watcher below.
  # No Install.WantedBy on purpose, so it never runs outside a session.
  systemd.user.services.sunshine-clipboard = {
    Unit = {
      Description = "Clipboard bridge for the active Sunshine session";
      After = [ "graphical-session.target" ];
      PartOf = [ "sunshine-session-watcher.service" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${clipboardBridgeScript}";
      Restart = "on-failure";
      RestartSec = "2s";
    };
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

  # ─── Phone integration ───────────────────────────────────────────────────────
  systemd.user.services.valent = {
    Unit = {
      Description = "Valent (KDE Connect for GTK)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.valent}/bin/valent --gapplication-service";
      Restart = "on-failure";
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

  systemd.user.services.aw-watchdog = {
    Unit = {
      Description = "ActivityWatch health check";
      After = [ "aw-server.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${awWatchdogScript}";
    };
  };

  systemd.user.timers.aw-watchdog = {
    Unit.Description = "ActivityWatch health check every 5 minutes";
    Timer = {
      OnCalendar = "*:0/5";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
