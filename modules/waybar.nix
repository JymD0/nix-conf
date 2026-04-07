{ pkgs, ... }:

let
  # Smart brightness control: brightnessctl for internal (eDP-1), ddcutil for external monitors
  brightnessScript = pkgs.writeShellScript "brightness-ctl" ''
    ACTION=$1
    STEP=10

    ACTIVE_MON=$(${pkgs.hyprland}/bin/hyprctl activeworkspace -j 2>/dev/null \
      | ${pkgs.jq}/bin/jq -r '.monitor // "eDP-1"')

    if [ "$ACTIVE_MON" = "eDP-1" ] || [ -z "$ACTIVE_MON" ]; then
      CUR=$(${pkgs.brightnessctl}/bin/brightnessctl g)
      MAX=$(${pkgs.brightnessctl}/bin/brightnessctl m)
      PCT=$(( CUR * 100 / MAX ))
      case "$ACTION" in
        up)
          if [ "$PCT" -ge 100 ]; then
            ${pkgs.brightnessctl}/bin/brightnessctl s 0 -q
            ${pkgs.swayosd}/bin/swayosd-client --brightness lower 2>/dev/null || true
          else
            ${pkgs.swayosd}/bin/swayosd-client --brightness raise 2>/dev/null || true
          fi
          ;;
        down) ${pkgs.swayosd}/bin/swayosd-client --brightness lower 2>/dev/null || true ;;
      esac
    else
      CUR=$(${pkgs.ddcutil}/bin/ddcutil getvcp 10 --brief 2>/dev/null | awk '{print $4}')
      CUR=''${CUR:-50}
      case "$ACTION" in
        up)
          if [ "$CUR" -ge 100 ]; then
            NEW=0
          else
            NEW=$(( CUR + STEP > 100 ? 100 : CUR + STEP ))
          fi
          ;;
        down) NEW=$(( CUR - STEP < 0 ? 0 : CUR - STEP )) ;;
      esac
      ${pkgs.ddcutil}/bin/ddcutil setvcp 10 "$NEW" 2>/dev/null
    fi

  '';

  brightnessStatusScript = pkgs.writeShellScript "brightness-status" ''
    PCT=$(${pkgs.ddcutil}/bin/ddcutil getvcp 10 --brief 2>/dev/null | awk '{print $4}')
    PCT=''${PCT:-"?"}
    echo "{\"text\": \"$PCT%\", \"tooltip\": \"External brightness: $PCT%\"}"
  '';

  powerMenu = pkgs.writeShellScript "power-menu" ''
    choice=$(printf '󰌾  Lock\n󰒲  Suspend\n󰍃  Log out\n󰋊  Hibernate\n󰑓  Reboot\n󰐥  Shut down' | \
      fuzzel --dmenu --prompt '⏻  ' --width 24 --lines 6 --no-icons)
    case "$choice" in
      *Lock*)        hyprlock ;;
      *Suspend*)     systemctl suspend-then-hibernate ;;
      *"Log out"*)   hyprctl dispatch exit 0 ;;
      *Hibernate*)
        notify-send -u critical -i system-hibernate "Hibernating…" "Saving RAM to disk"
        systemctl hibernate
        ;;
      *Reboot*)      systemctl reboot ;;
      *"Shut down"*) systemctl poweroff ;;
    esac
  '';

  # Live watt draw — shown next to battery module, no icon (battery module already has one)
  powerDrawScript = pkgs.writeShellScript "power-draw" ''
    BAT=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
    [ -z "$BAT" ] && { printf '{"text":"","tooltip":"No battery found","class":""}\n'; exit 0; }
    STATUS=$(cat "$BAT/status" 2>/dev/null || echo "Unknown")
    if [ -f "$BAT/power_now" ]; then
      POWER=$(cat "$BAT/power_now")
    else
      CURRENT=$(cat "$BAT/current_now" 2>/dev/null || echo 0)
      VOLTAGE=$(cat "$BAT/voltage_now" 2>/dev/null || echo 0)
      POWER=$(( CURRENT * VOLTAGE / 1000000 ))
    fi
    if [ "$POWER" -gt 0 ] 2>/dev/null; then
      WATTS=$(echo "scale=1; $POWER / 1000000" | ${pkgs.bc}/bin/bc)
    else
      WATTS="0"
    fi
    case "$STATUS" in
      Discharging)
        printf '{"text":"-%sW","tooltip":"Drawing %sW from battery","class":"discharging"}\n' "$WATTS" "$WATTS" ;;
      Charging)
        # Suppress 0W — happens when BIOS charge limit is reached
        if [ "$WATTS" = "0" ]; then
          printf '{"text":"","tooltip":"Plugged in (charge limit reached)","class":"full"}\n'
        else
          printf '{"text":"+%sW","tooltip":"Charging at %sW","class":"charging"}\n' "$WATTS" "$WATTS"
        fi ;;
      Full|"Not charging")
        printf '{"text":"","tooltip":"Battery full","class":"full"}\n' ;;
      *)
        printf '{"text":"","tooltip":"%s","class":""}\n' "$STATUS" ;;
    esac
  '';

  # ActivityWatch — time tracking waybar module (AFK-filtered via query API)
  timetrackScript = pkgs.writeShellScript "timetrack" ''
    JQ=${pkgs.jq}/bin/jq
    CURL=${pkgs.curl}/bin/curl

    TODAY=$(date +%Y-%m-%dT00:00:00%:z)
    NOW=$(date +%Y-%m-%dT%H:%M:%S%:z)

    PAYLOAD=$($JQ -nc --arg p "$TODAY/$NOW" '{
      timeperiods: [$p],
      query: [
        "events = query_bucket(find_bucket(\"aw-watcher-window_\"));",
        "not_afk = query_bucket(find_bucket(\"aw-watcher-afk_\"));",
        "not_afk = filter_keyvals(not_afk, \"status\", [\"not-afk\"]);",
        "events = filter_period_intersect(events, not_afk);",
        "events = merge_events_by_keys(events, [\"app\"]);",
        "events = sort_by_duration(events);",
        "RETURN = events;"
      ]
    }')

    EVENTS=$($CURL -s -X POST "http://localhost:5600/api/0/query/" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" 2>/dev/null | $JQ '.[0] // []' 2>/dev/null)

    if [ -z "$EVENTS" ] || [ "$EVENTS" = "null" ] || [ "$EVENTS" = "[]" ]; then
      printf '{"text":"󱎫 --","tooltip":"No activity data","class":"idle"}\n'
      exit 0
    fi

    TOTAL_SECS=$(echo "$EVENTS" | $JQ '[.[].duration] | add // 0 | floor')
    MINS=$((TOTAL_SECS / 60))

    if [ "$MINS" -lt 1 ]; then
      printf '{"text":"󱎫 --","tooltip":"No activity data","class":"idle"}\n'
      exit 0
    fi

    HOURS=$((MINS / 60))
    REM=$((MINS % 60))

    if [ "$HOURS" -gt 0 ]; then
      TEXT="󱎫 ''${HOURS}h ''${REM}m"
    else
      TEXT="󱎫 ''${MINS}m"
    fi

    if [ "$HOURS" -ge 8 ]; then
      CLASS="critical"
    elif [ "$HOURS" -ge 6 ]; then
      CLASS="warning"
    else
      CLASS="normal"
    fi

    TOOLTIP=$(echo "$EVENTS" | $JQ -r '
      sort_by(-.duration)
      | .[0:5]
      | .[]
      | ((.data.app // "?") + "  " + (
          if .duration >= 3600 then
            ((.duration / 3600 | floor | tostring) + "h " + (.duration % 3600 / 60 | floor | tostring) + "m")
          elif .duration >= 60 then
            ((.duration / 60 | floor | tostring) + "m")
          else
            "~0m"
          end
        ))
    ' 2>/dev/null)

    [ -z "$TOOLTIP" ] && TOOLTIP="No breakdown available"

    $JQ -nc --arg text "$TEXT" --arg tooltip "$TOOLTIP" --arg class "$CLASS" \
      '{text: $text, tooltip: $tooltip, class: $class}'
  '';

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

  # Adjust LED matrix brightness by +-10%, wakes on scroll-up if sleeping
  ledmatrixBrightnessScript = pkgs.writeShellScript "ledmatrix-brightness" ''
    set -euo pipefail
    DEV="/dev/ttyACM0"
    [ ! -e "$DEV" ] && exit 0
    STATEFILE="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-sleeping"
    STEP=10
    RAW=$(inputmodule-control --serial-dev "$DEV" led-matrix --brightness 2>/dev/null)
    CUR=$(echo "$RAW" | awk '{print $NF}')
    CUR="''${CUR:-50}"
    case "$CUR" in
      *[!0-9]*|'''') CUR=50 ;;
    esac
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

in
{
  programs.waybar =
    let
      # ── Shared module definitions (identical on all outputs) ──────────────
      sharedModules = {
        "hyprland/workspaces" = {
          format = "{id}";
          on-click = "activate";
          sort-by-number = true;
        };

        "hyprland/window" = {
          format = "{}";
          max-length = 50;
          separate-outputs = true;
          rewrite = {
            "^$" = "Desktop";
          };
        };

        clock = {
          interval = 1;
          format = " {:%H:%M:%S}";
          format-alt = " {:%a, %d %b %Y}";
          on-click-right = "kitty --hold --class floating-calendar --title Calendar -e khal interactive";
          tooltip = false;
        };

        "custom/media" = {
          format = "{icon}{}";
          return-type = "json";
          format-icons = {
            Playing = "";
            Paused = "󰏤 ";
            Stopped = "󰓛 ";
          };
          max-length = 35;
          exec = ''playerctl -a metadata --format '{"text": "{{artist}} - {{title}}", "tooltip": "{{playerName}}: {{title}}", "alt": "{{status}}", "class": "{{status}}"}' -F 2>/dev/null | sed 's/"text": " - "/"text": ""/g' '';
          on-click = "playerctl play-pause";
          on-click-right = "playerctl next";
          on-scroll-up = "playerctl next";
          on-scroll-down = "playerctl previous";
        };

        cpu = {
          interval = 3;
          format = "{usage}%";
          tooltip-format = "CPU: {usage}%\nLoad: {load}";
          on-click = "kitty -e btop";
        };

        memory = {
          interval = 5;
          format = "{percentage}%";
          tooltip-format = "RAM: {used:0.1f}G / {total:0.1f}G";
          on-click = "kitty -e btop";
        };

        temperature = {
          critical-threshold = 80;
          interval = 5;
          format = "{temperatureC}°C";
          format-critical = "󰸁 {temperatureC}°C";
          format-icons = [
            ""
            ""
            ""
            ""
            ""
          ];
          tooltip-format = "CPU temp: {temperatureC}°C";
        };

        battery = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon} {capacity}%";
          format-charging = "󰂄 {capacity}%";
          format-plugged = "󰚥 {capacity}%";
          format-icons = [
            "󰁺"
            "󰁻"
            "󰁼"
            "󰁽"
            "󰁾"
            "󰁿"
            "󰂀"
            "󰂁"
            "󰂂"
            "󰁹"
          ];
          tooltip-format = "Battery: {capacity}%\nPower: {power}W\nTime remaining: {time}";
        };

        "custom/power-draw" = {
          interval = 5;
          return-type = "json";
          exec = "${powerDrawScript}";
          format = "{}";
        };

        network = {
          format-wifi = "󰤨 {essid}";
          format-ethernet = "󰈀 {ipaddr}";
          format-disconnected = "󰤭 Offline";
          tooltip-format-wifi = "{essid}\n{signaldBm} dBm  ↑{bandwidthUpBits} ↓{bandwidthDownBits}";
          tooltip-format-ethernet = "{ifname}: {ipaddr}";
          on-click = "kitty -e nmtui";
        };

        pulseaudio = {
          format = "{icon} {volume}%";
          format-muted = "󰝟 muted";
          format-icons = {
            default = [
              "󰕿"
              "󰖀"
              "󰕾"
            ];
            headphone = [ "󰋋" ];
            headset = [ "󰋎" ];
          };
          scroll-step = 2;
          on-click = "${pkgs.swayosd}/bin/swayosd-client --output-volume mute-toggle";
          on-click-right = "kitty -e pulsemixer";
          tooltip-format = "{desc}\nVolume: {volume}%";
        };

        backlight = {
          format = "{icon} {percent}%";
          format-icons = [
            "󰃞"
            "󰃟"
            "󰃠"
          ];
          on-click = "${brightnessScript} up";
          on-click-right = "kitty --hold -e ${pkgs.brightnessctl}/bin/brightnessctl";
          on-scroll-up = "${pkgs.swayosd}/bin/swayosd-client --brightness raise";
          on-scroll-down = "${pkgs.swayosd}/bin/swayosd-client --brightness lower";
          tooltip-format = "Brightness: {percent}%";
        };

        "custom/brightness" = {
          interval = 5;
          return-type = "json";
          exec = "${brightnessStatusScript}";
          format = "󰃠  {}";
          on-scroll-up = "${brightnessScript} up";
          on-scroll-down = "${brightnessScript} down";
          on-click = "${brightnessScript} up";
        };

        # SwayOSD handles internal brightness natively — the custom/brightness
        # module with ddcutil is only shown on external monitors (see modules-right).

        bluetooth = {
          format = "󰂯 {status}";
          format-connected = "󰂱 {device_alias}";
          format-off = "󰂲";
          tooltip-format = "{controller_alias}\n{controller_address}\n\n{num_connections} connected";
          on-click = "blueman-manager";
        };

        "power-profiles-daemon" = {
          format = "{icon}";
          tooltip-format = "Power profile: {profile}\nDriver: {driver}";
          format-icons = {
            default = "󰾅";
            performance = "󰓅";
            balanced = "󰾅";
            "power-saver" = "󰌪";
          };
        };

        "custom/tailscale" = {
          interval = 5;
          return-type = "json";
          exec = ''bash -c 'status=$(tailscale status --json 2>/dev/null); if [ $? -eq 0 ]; then state=$(echo "$status" | ${pkgs.jq}/bin/jq -r ".BackendState"); ip=$(echo "$status" | ${pkgs.jq}/bin/jq -r ".TailscaleIPs[0] // empty"); exit_node=$(echo "$status" | ${pkgs.jq}/bin/jq -r "if .ExitNodeStatus.Online then .ExitNodeStatus.TailscaleIPs[0] else empty end // empty"); if [ "$state" = "Running" ]; then tooltip="Tailscale: connected"; [ -n "$ip" ] && tooltip="$tooltip\nIP: $ip"; [ -n "$exit_node" ] && tooltip="$tooltip\nExit node active"; echo "{\"text\": \"on\", \"tooltip\": \"$tooltip\", \"class\": \"connected\"}"; else echo "{\"text\": \"off\", \"tooltip\": \"Tailscale: $state\", \"class\": \"disconnected\"}"; fi; else echo "{\"text\": \"off\", \"tooltip\": \"Tailscale: not running\", \"class\": \"disconnected\"}"; fi' '';
          format = "󰖂 {}";
          on-click = "tailscale up";
          on-click-right = "tailscale down";
        };

        "custom/notification" = {
          interval = 3;
          format = "{}";
          exec = ''bash -c 'dnd=$(swaync-client -D 2>/dev/null); n=$(swaync-client -c 2>/dev/null || echo 0); [ "$dnd" = "true" ] && echo "󰪑 DND" || { [ "$n" -gt 0 ] && echo "󰂚 $n" || echo "󰂜"; }' '';
          on-click = "swaync-client -t -sw";
          on-click-right = "swaync-client -d -sw";
          tooltip = false;
        };

        "custom/youtube-sync" = {
          interval = 2;
          return-type = "json";
          signal = 8;
          exec = ''bash -c 'if [ -f "$HOME/.claude/youtube-sync" ]; then printf "{\"text\":\"󰝚\",\"tooltip\":\"Auto media sync: on (click to disable)\",\"class\":\"enabled\"}\\n"; else printf "{\"text\":\"󰝚\",\"tooltip\":\"Auto media sync: off (click to enable)\",\"class\":\"disabled\"}\\n"; fi' '';
          on-click = ''bash -c 'f="$HOME/.claude/youtube-sync"; [ -f "$f" ] && rm "$f" || touch "$f"; pkill -RTMIN+8 waybar 2>/dev/null || true' '';
          format = "{}";
        };

        "custom/power" = {
          format = "⏻";
          tooltip = false;
          on-click = "${powerMenu}";
        };

        "custom/timetrack" = {
          interval = 60;
          return-type = "json";
          exec = "${timetrackScript}";
          format = "{}";
          on-click = "xdg-open \"http://localhost:5600/#/activity/$(hostname)/view/\"";
        };

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

        tray = {
          icon-size = 16;
          spacing = 8;
        };
      };

      # ── Shared layout (same module list on every output) ──────────────────
      sharedLayout = {
        layer = "top";
        position = "top";
        spacing = 0;
        fixed-center = true;
        margin-left = 12;
        margin-right = 12;
        margin-bottom = 0;
        modules-left = [
          "hyprland/workspaces"
          "hyprland/window"
        ];
        modules-center = [ "clock" ];
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
          "custom/power-draw"
          "network"
          "custom/tailscale"
          "bluetooth"
          "power-profiles-daemon"
          "custom/notification"
          "tray"
          "custom/power"
        ];
      };
    in
    {
      enable = true;
      settings = [
        # Laptop built-in display — larger
        (
          sharedLayout
          // sharedModules
          // {
            output = "eDP-1";
            height = 42;
            margin-top = 8;
          }
        )
        # External monitors — compact (no backlight: /sys/class/backlight is internal-only)
        (
          sharedLayout
          // sharedModules
          // {
            output = "!eDP-1";
            height = 34;
            margin-top = 6;
            modules-right = [
              "custom/timetrack"
              "custom/media"
              "custom/youtube-sync"
              "cpu"
              "memory"
              "temperature"
              "pulseaudio"
              "custom/brightness"
              "battery"
              "custom/power-draw"
              "network"
              "custom/tailscale"
              "bluetooth"
              "power-profiles-daemon"
              "custom/notification"
              "tray"
              "custom/power"
            ];
          }
        )
      ];

      style = ''
        * {
          font-family: "JetBrainsMono Nerd Font", "Font Awesome 6 Free", monospace;
          font-size: 14px;
          min-height: 0;
          border: none;
          border-radius: 0;
          transition: color 0.2s ease, background-color 0.2s ease;
        }

        /* ── Bar window — transparent so the pills float ── */
        window#waybar {
          background: transparent;
          color: #f8f8f2;
        }

        /* ── Floating pill groups ── */
        .modules-left,
        .modules-center,
        .modules-right {
          background: #282a36;
          border-radius: 14px;
          padding: 0 8px;
          margin: 5px 4px;
          box-shadow: none;
        }

        /* Pack the right pill toward center instead of spreading across the bar */
        .modules-right {
          margin-left: 0;
        }

        /* ── Workspaces ── */
        #workspaces {
          padding: 0 2px;
        }

        #workspaces button {
          padding: 0;
          min-width: 28px;
          color: #6272a4;
          background: transparent;
          border-radius: 10px;
          margin: 4px 2px;
          font-weight: bold;
        }

        #workspaces button label {
          min-width: 28px;
        }

        #workspaces button:hover {
          background: rgba(98, 114, 164, 0.25);
          color: #f8f8f2;
          border-radius: 10px;
        }

        /* Active workspace: only the text colour changes, no background fill */
        #workspaces button.active {
          color: #bd93f9;
          background: transparent;
          border-radius: 10px;
        }

        #workspaces button.urgent {
          background: rgba(255, 85, 85, 0.2);
          color: #ff5555;
          border-radius: 10px;
        }

        /* ── Window title ── */
        #window {
          color: rgba(248, 248, 242, 0.7);
          font-style: italic;
          padding: 0 6px 0 6px;
        }
        #window.empty {
          padding: 0 6px;
        }

        /* ── Clock ── */
        #clock {
          color: #f8f8f2;
          font-weight: bold;
          font-size: 15px;
          padding: 2px 10px 0 10px;
        }

        /* ── Shared right-module padding ── */
        #cpu,
        #memory,
        #temperature,
        #network,
        #pulseaudio,
        #backlight,
        #bluetooth,
        #battery,
        #power-profiles-daemon,
        #custom-media,
        #custom-youtube-sync,
        #custom-tailscale,
        #custom-power-draw,
        #custom-notification,
        #tray,
        #custom-power {
          padding: 0 10px;
        }

        /* ── Module accent colours ── */
        #custom-timetrack         { color: #f1fa8c; padding: 0 10px; }
        #custom-timetrack.warning  { color: #ffb86c; }
        #custom-timetrack.critical { color: #ff5555; }
        #custom-media.empty { padding: 0; margin: 0; }
        #custom-media        { color: #50fa7b; }
        #custom-media.Paused { color: #6272a4; }

        #custom-youtube-sync          { color: #6272a4; }
        #custom-youtube-sync.enabled  { color: #bd93f9; }

        #cpu    { color: #ff79c6; }
        #memory { color: #bd93f9; }

        #temperature          { color: #ffb86c; }
        #temperature.critical { color: #ff5555; }

        #pulseaudio       { color: #bd93f9; }
        #pulseaudio.muted { color: #6272a4; }

        #backlight,
        #custom-brightness { color: #f1fa8c; }

        #custom-ledmatrix       { color: #bd93f9; padding: 0 10px; }
        #custom-ledmatrix.off   { color: #6272a4; }

        #battery          { color: #50fa7b; }
        #battery.warning  { color: #f1fa8c; }
        #battery.critical {
          color: #ff5555;
          animation: blink 0.6s steps(1) infinite;
        }
        @keyframes blink {
          to { color: rgba(248, 248, 242, 0.7); }
        }

        #custom-power-draw                { color: #ffb86c; }
        #custom-power-draw.charging       { color: #50fa7b; }
        #custom-power-draw.full           { color: #50fa7b; }

        #network             { color: #8be9fd; }
        #network.disconnected { color: #ff5555; }

        #custom-tailscale              { color: #8be9fd; }
        #custom-tailscale.disconnected { color: #6272a4; }

        #bluetooth     { color: #8be9fd; }
        #bluetooth.off { color: #6272a4; }

        #power-profiles-daemon { color: #ffb86c; }

        /* ── Notification ── */
        #custom-notification {
          color: #f8f8f2;
        }
        #custom-notification.dnd {
          color: #6272a4;
        }

        /* ── Power button ── */
        #custom-power {
          color: #ff5555;
          font-size: 16px;
        }
        #custom-power:hover {
          color: #ff8080;
        }

        /* ── Tray ── */
        #tray.empty {
          padding: 0;
          margin: 0;
        }
        #tray > .passive {
          -gtk-icon-effect: dim;
        }
        #tray > .needs-attention {
          -gtk-icon-effect: highlight;
          background: rgba(255, 85, 85, 0.2);
          border-radius: 6px;
        }

        /* ── Tooltips ── */
        tooltip {
          background: rgba(40, 42, 54, 0.97);
          border: 1px solid rgba(98, 114, 164, 0.5);
          border-radius: 10px;
          padding: 2px 4px;
        }
        tooltip label {
          color: #f8f8f2;
          font-size: 13px;
        }

        /* ── External monitor overrides (smaller, compact) ── */
        /* waybar adds the output name as a CSS class on window#waybar        */
        /* eDP-1 = laptop built-in; everything else gets the rules below.     */
        window#waybar:not(.eDP-1) * {
          font-size: 12px;
        }
        window#waybar:not(.eDP-1) #clock {
          font-size: 13px;
          padding: 0 12px;
        }
        window#waybar:not(.eDP-1) .modules-left,
        window#waybar:not(.eDP-1) .modules-center,
        window#waybar:not(.eDP-1) .modules-right {
          margin: 4px 4px;
        }
        window#waybar:not(.eDP-1) #workspaces button {
          padding: 0;
          min-width: 24px;
          margin: 3px 1px;
        }
        window#waybar:not(.eDP-1) #workspaces button label {
          min-width: 24px;
        }
        window#waybar:not(.eDP-1) #custom-power {
          font-size: 14px;
        }
        window#waybar:not(.eDP-1) #cpu,
        window#waybar:not(.eDP-1) #memory,
        window#waybar:not(.eDP-1) #temperature,
        window#waybar:not(.eDP-1) #network,
        window#waybar:not(.eDP-1) #pulseaudio,
        window#waybar:not(.eDP-1) #backlight,
        window#waybar:not(.eDP-1) #custom-brightness,
        window#waybar:not(.eDP-1) #custom-ledmatrix,
        window#waybar:not(.eDP-1) #bluetooth,
        window#waybar:not(.eDP-1) #battery,
        window#waybar:not(.eDP-1) #power-profiles-daemon,
        window#waybar:not(.eDP-1) #custom-timetrack,
        window#waybar:not(.eDP-1) #custom-media,
        window#waybar:not(.eDP-1) #custom-youtube-sync,
        window#waybar:not(.eDP-1) #custom-tailscale,
        window#waybar:not(.eDP-1) #custom-notification,
        window#waybar:not(.eDP-1) #custom-power-draw,
        window#waybar:not(.eDP-1) #tray,
        window#waybar:not(.eDP-1) #custom-power {
          padding: 0 8px;
        }
      '';
    };
}
