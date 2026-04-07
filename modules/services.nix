{ pkgs, user, ... }:

let
  # AC plug/unplug notification daemon
  acMonitorScript = pkgs.writeShellScript "ac-monitor" ''
    ${pkgs.upower}/bin/upower --monitor | while IFS= read -r line; do
      if echo "$line" | grep -q "line_power"; then
        sleep 0.5
        AC_PATH=$(grep -rl "Mains" /sys/class/power_supply/*/type 2>/dev/null | head -1 | xargs -I{} dirname {})
        ONLINE=$(cat "$AC_PATH/online" 2>/dev/null || echo "?")
        if [ "$ONLINE" = "1" ]; then
          ${pkgs.libnotify}/bin/notify-send -u low -t 3000 "󰚥 AC Connected" "Plugged in"
        elif [ "$ONLINE" = "0" ]; then
          ${pkgs.libnotify}/bin/notify-send -u low -t 3000 "󰁾 AC Disconnected" "Running on battery"
        fi
      fi
    done
  '';

  # Low battery warning + auto-hibernate at 5%
  batteryMonitorScript = pkgs.writeShellScript "battery-monitor" ''
    CAPACITY=$(cat /sys/class/power_supply/BAT1/capacity 2>/dev/null || echo 100)
    STATUS=$(cat /sys/class/power_supply/BAT1/status 2>/dev/null || echo "Unknown")
    STATE_FILE="''${XDG_RUNTIME_DIR:-/tmp}/battery-notified"

    [ "$STATUS" != "Discharging" ] && { rm -f "$STATE_FILE"; exit 0; }

    LAST=$(cat "$STATE_FILE" 2>/dev/null || echo 100)

    if   [ "$CAPACITY" -le 5  ] && [ "$LAST" -gt 5  ]; then
      ${pkgs.libnotify}/bin/notify-send -u critical -t 0 "󰁺 Battery Critical" "At ''${CAPACITY}% — hibernating in 30s"
      echo 5 > "$STATE_FILE"
      sleep 30
      systemctl hibernate
    elif [ "$CAPACITY" -le 10 ] && [ "$LAST" -gt 10 ]; then
      ${pkgs.libnotify}/bin/notify-send -u critical -t 0 "󰁻 Battery Low" "At ''${CAPACITY}% — please plug in"
      echo 10 > "$STATE_FILE"
    elif [ "$CAPACITY" -le 20 ] && [ "$LAST" -gt 20 ]; then
      ${pkgs.libnotify}/bin/notify-send -u normal -t 8000 "󰁼 Battery Warning" "At ''${CAPACITY}%"
      echo 20 > "$STATE_FILE"
    fi
  '';

in
{
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

  # ─── MetaMCP proxy service ──────────────────────────────────────────────────
  systemd.user.services.metamcp-proxy = {
    Unit = {
      Description = "MetaMCP sanitizing proxy";
      After = [ "network-online.target" "gnome-keyring-daemon.service" ];
      Wants = [ "gnome-keyring-daemon.service" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.nodejs}/bin/node /home/${user.username}/Projects/mcp/metamcp-proxy.mjs";
      Restart = "always";
      RestartSec = "10s";
      Environment = [
        "PORT=12100"
        "METAMCP_URL=${user.metamcpUrl}"
      ];
    };
    Install.WantedBy = [ "default.target" ];
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
