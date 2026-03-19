{ config, pkgs, lib, claude-code, ... }:

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
      *Suspend*)     systemctl suspend ;;
      *"Log out"*)   hyprctl dispatch exit 0 ;;
      *Hibernate*)
        notify-send -u critical -i system-hibernate "Hibernating…" "Saving RAM to disk — do not close the lid"
        systemctl hibernate
        ;;
      *Reboot*)      systemctl reboot ;;
      *"Shut down"*) systemctl poweroff ;;
    esac
  '';

  # Live watt draw — shown next to battery module, no icon (battery module already has one)
  powerDrawScript = pkgs.writeShellScript "power-draw" ''
    STATUS=$(cat /sys/class/power_supply/BAT1/status 2>/dev/null || echo "Unknown")
    if [ -f /sys/class/power_supply/BAT1/power_now ]; then
      POWER=$(cat /sys/class/power_supply/BAT1/power_now)
    else
      CURRENT=$(cat /sys/class/power_supply/BAT1/current_now 2>/dev/null || echo 0)
      VOLTAGE=$(cat /sys/class/power_supply/BAT1/voltage_now 2>/dev/null || echo 0)
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
  home.username = "yourUsername";
  home.homeDirectory = "/home/yourUsername";
  home.stateVersion = "24.11";

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

  # Suppress nixpkgs version mismatch warnings
  home.enableNixpkgsReleaseCheck = false;

  # ─── Variety setup (mutable files — variety needs chmod and write access) ────
  home.activation.varietySetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    variety_dir="$HOME/.config/variety"
    scripts_dir="$variety_dir/scripts"
    mkdir -p "$scripts_dir" "$variety_dir/Downloaded" "$variety_dir/Favorites" "$variety_dir/Fetched"

    # Only write config if not yet present (let variety manage it after first deploy)
    if [ ! -f "$variety_dir/variety.conf" ] || [ -L "$variety_dir/variety.conf" ]; then
      rm -f "$variety_dir/variety.conf"
      cat > "$variety_dir/variety.conf" << 'CONF'
# Wallpaper change settings
change_enabled = True
change_on_start = True
change_interval = 1800

# Download settings
download_enabled = True
download_interval = 60
download_folder = ~/.config/variety/Downloaded
quota_enabled = True
quota_size = 500

# Folders
favorites_folder = ~/.config/variety/Favorites
fetched_folder = ~/.config/variety/Fetched

# Image filtering
safe_mode = True
min_size_enabled = True
min_size = 80
use_landscape_enabled = True
lightness_enabled = False

[sources]
src1 = True|favorites|The Favorites folder
src2 = True|fetched|The Fetched folder
src3 = True|unsplash|High-resolution photos from Unsplash.com
src4 = True|bing|Bing Photo of the Day
src5 = True|wallhaven|nature dark
src6 = True|wallhaven|landscape
src7 = False|apod|NASA's Astronomy Picture of the Day
src8 = False|desktoppr|Random wallpapers from Desktoppr.co
src9 = False|earth|World Sunlight Map - live wallpaper from Die.net

[filters]
CONF
    fi

    cat > "$scripts_dir/set_wallpaper" << 'SCRIPT'
#!/bin/sh
if [ -z "$1" ]; then
  exit 1
fi
${pkgs.swww}/bin/swww img "$1" \
  --transition-type fade \
  --transition-duration 1 \
  --transition-fps 60
ln -sf "$1" "$HOME/.current-wallpaper"
SCRIPT
    chmod +x "$scripts_dir/set_wallpaper"

    cat > "$scripts_dir/get_wallpaper" << 'SCRIPT'
#!/bin/sh
${pkgs.swww}/bin/swww query | grep -oP 'image: \K.*' | head -1
SCRIPT
    chmod +x "$scripts_dir/get_wallpaper"

    cat > "$scripts_dir/set_lock_screen" << 'SCRIPT'
#!/bin/sh
exit 0
SCRIPT
    chmod +x "$scripts_dir/set_lock_screen"
  '';

  # ─── Fonts ─────────────────────────────────────────────────────────────────────
  fonts.fontconfig.enable = true;

  # ─── Packages ───────────────────────────────────────────────────────────────────
  home.packages = (with pkgs; [
    # Screenshots
    grim
    slurp
    satty

    # QoL tools
    cliphist
    bemoji

    # File manager
    nemo

    # Notifications (libnotify needed by various apps)
    libnotify

    # Bluetooth & network (needed by Waybar on-click actions)
    blueman
    networkmanagerapplet

    # Display management
    wdisplays
    kanshi

    # Lock screen
    hyprlock

    # Terminal multiplexer
    tmux

    # System info
    fastfetch
    btop
    upower     # battery info (upower -i $(upower -e | grep bat))
    powerstat  # real-time per-process power consumption
    acpi       # quick battery/AC status

    # Audio mixer
    pulsemixer

    # Media control
    playerctl

    # Apps
    discord
    pinta

    # Fonts
    noto-fonts-color-emoji
    jetbrains-mono
    font-awesome
    nerd-fonts.jetbrains-mono

    # Icons
    papirus-icon-theme

    # SSH & File Transfer
    termscp
    sshpass

    # Wallpaper
    swww
    variety

    # Calendar
    khal
    vdirsyncer

    # LaTeX
    texliveMedium

    # Utilities
    ripgrep
    fd
    jq
    unzip
    p7zip

    # Jupyter
    (python3.withPackages (ps: with ps; [
      jupyter
      notebook
      numpy
      pandas
      matplotlib
      torchvision
    ]))

    # Misc
    xdg-utils

    # Camera (webcam viewer / v4l2 tools for OBS)
    v4l-utils

    # Music
    spotify
  ]) ++ [
    claude-code.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # ─── XDG dirs ──────────────────────────────────────────────────────────────────
  xdg = {
    enable = true;
    userDirs = {
      enable = true;
      createDirectories = true;
      desktop    = "${config.home.homeDirectory}/Desktop";
      documents  = "${config.home.homeDirectory}/Documents";
      download   = "${config.home.homeDirectory}/Downloads";
      music      = "${config.home.homeDirectory}/Music";
      pictures   = "${config.home.homeDirectory}/Pictures";
      publicShare = "${config.home.homeDirectory}/Public";
      templates  = "${config.home.homeDirectory}/Templates";
      videos     = "${config.home.homeDirectory}/Videos";
    };

    desktopEntries = {
      blueman-adapters = {
        name = "Bluetooth Adapters";
        comment = "Set Bluetooth Adapter Properties";
        exec = "blueman-adapters";
        icon = "blueman";
        terminal = false;
        categories = [ "Settings" "HardwareSettings" ];
      };
      khal = {
        name = "Calendar";
        comment = "Terminal calendar application";
        exec = "kitty --hold --class floating-calendar --title Calendar -e khal interactive";
        icon = "calendar";
        terminal = false;
        categories = [ "Calendar" ];
      };
    };

    configFile = {
      # ─── khal calendar config ─────────────────────────────────────────────────
      "khal/config".text = ''
        [calendars]

        [[personal]]
        path = ~/.local/share/vdirsyncer/calendar/*
        type = discover
        color = light magenta

        [locale]
        timeformat = %H:%M
        dateformat = %d.%m.%Y
        longdateformat = %d.%m.%Y
        datetimeformat = %d.%m.%Y %H:%M
        longdatetimeformat = %d.%m.%Y %H:%M
        default_timezone = Europe/Vienna
        firstweekday = 0

        [default]
        default_calendar = personal
      '';

      # ─── vdirsyncer config ────────────────────────────────────────────────────
      "vdirsyncer/config".text = ''
        [general]
        status_path = "~/.local/share/vdirsyncer/status/"

        [pair personal_calendar]
        a = "personal_calendar_local"
        b = "personal_calendar_remote"
        collections = ["from a", "from b"]
        metadata = ["color"]

        [storage personal_calendar_local]
        type = "filesystem"
        path = "~/.local/share/vdirsyncer/calendar/"
        fileext = ".ics"

        [storage personal_calendar_remote]
        type = "google_calendar"
        token_file = "~/.local/share/vdirsyncer/google_token"
        client_id = ""
        client_secret = ""
      '';
    };
  };

  # ─── Kitty Terminal ───────────────────────────────────────────────────────────
  programs.kitty = {
    enable = true;
    font = {
      name = "JetBrains Mono";
      size = 12;
    };
    settings = {
      background_opacity = "0.95";
      window_padding_width = 8;
      tab_bar_style = "powerline";
      tab_bar_edge = "top";
      copy_on_select = true;
      enable_audio_bell = false;
      confirm_os_window_close = 0;
      repaint_delay = 10;
      input_delay = 3;
      sync_to_monitor = true;

      foreground           = "#f8f8f2";
      background           = "#282a36";
      selection_foreground = "#ffffff";
      selection_background = "#44475a";
      cursor               = "#f8f8f2";
      cursor_text_color    = "#282a36";
      url_color            = "#8be9fd";
      url_style            = "curly";
      color0  = "#21222c"; color8  = "#6272a4";
      color1  = "#ff5555"; color9  = "#ff6e6e";
      color2  = "#50fa7b"; color10 = "#69ff94";
      color3  = "#f1fa8c"; color11 = "#ffffa5";
      color4  = "#bd93f9"; color12 = "#d6acff";
      color5  = "#ff79c6"; color13 = "#ff92df";
      color6  = "#8be9fd"; color14 = "#a4ffff";
      color7  = "#f8f8f2"; color15 = "#ffffff";
    };
    shellIntegration.enableBashIntegration = true;
    shellIntegration.enableZshIntegration = true;
  };

  # ─── Fuzzel ────────────────────────────────────────────────────────────────────
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        font = "JetBrainsMono Nerd Font:size=13";
        dpi-aware = "auto";
        icon-theme = "Papirus-Dark";
        icons-enabled = true;
        terminal = "kitty";
        layer = "overlay";
        exit-on-keyboard-focus-loss = true;
        width = 35;
        lines = 10;
        horizontal-pad = 16;
        vertical-pad = 12;
        inner-pad = 6;
        border-radius = 10;
      };
      colors = {
        background = "282a36ee";
        text       = "f8f8f2ff";
        match      = "bd93f9ff";
        selection  = "44475aff";
        selection-text = "f8f8f2ff";
        selection-match = "ff79c6ff";
        border     = "bd93f9ff";
      };
      border = {
        width = 2;
        radius = 10;
      };
    };
  };

  # ─── VS Code ──────────────────────────────────────────────────────────────────
  programs.vscode = {
    enable = true;
    profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        jnoortheen.nix-ide
        dracula-theme.theme-dracula
        eamodio.gitlens
      ];
      userSettings = {
        "workbench.colorTheme"              = "Dracula";
        "editor.fontSize"                   = 14;
        "editor.fontFamily"                 = "'JetBrains Mono', 'monospace'";
        "editor.formatOnSave"               = true;
        "editor.minimap.enabled"            = false;
        "files.autoSave"                    = "afterDelay";
        "terminal.integrated.fontSize"      = 13;
        "terminal.integrated.defaultProfile.linux" = "bash";
        "git.autofetch"                     = true;
      };
    };
  };

  # ─── OBS Studio ───────────────────────────────────────────────────────────────
  programs.obs-studio = {
    enable = true;
    plugins = with pkgs.obs-studio-plugins; [
      wlrobs              # Wayland screen capture (pipewire/wlroots)
      obs-pipewire-audio-capture # per-app audio capture via PipeWire
      obs-backgroundremoval   # virtual background / chroma key alternative
      obs-gstreamer       # GStreamer video/audio source support
    ];
  };

  # ─── Git ──────────────────────────────────────────────────────────────────────
  programs.git = {
    enable = true;
    settings = {
      user = {
        name  = "Your Name";
        email = "your.email@example.com";
      };
    };
  };

  # ─── Bash ─────────────────────────────────────────────────────────────────────
  programs.bash = {
    enable = true;
    shellAliases = {
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#$(hostname)";
      update  = "cd /etc/nixos && sudo nix flake update && sudo nixos-rebuild switch --flake .#$(hostname)";
      scpget  = "termscp";
      battery = "upower -i $(upower -e | grep -i bat | head -1)";
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      format = "$all";
      palette = "dracula";
      palettes.dracula = {
        purple = "#bd93f9";
        cyan   = "#8be9fd";
        green  = "#50fa7b";
        red    = "#ff5555";
        yellow = "#f1fa8c";
        pink   = "#ff79c6";
        orange = "#ffb86c";
      };
      character = {
        success_symbol = "[>](bold green)";
        error_symbol   = "[>](bold red)";
      };
      directory.style = "bold cyan";
      git_branch.style = "bold purple";
    };
  };

  # ─── Waybar ───────────────────────────────────────────────────────────────────
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
          interval   = 1;
          format     = " {:%H:%M:%S}";
          format-alt = " {:%a, %d %b %Y}";
          on-click-right = "kitty --hold --class floating-calendar --title Calendar -e khal interactive";
          tooltip = false;
        };

        "custom/media" = {
          format = "{icon}  {}";
          return-type = "json";
          format-icons = {
            Playing = "";
            Paused  = "󰏤";
            Stopped = "󰓛";
          };
          max-length = 35;
          exec = ''playerctl -a metadata --format '{"text": "{{artist}} - {{title}}", "tooltip": "{{playerName}}: {{title}}", "alt": "{{status}}", "class": "{{status}}"}' -F 2>/dev/null'';
          on-click       = "playerctl play-pause";
          on-click-right = "playerctl next";
          on-scroll-up   = "playerctl next";
          on-scroll-down = "playerctl previous";
        };

        cpu = {
          interval = 3;
          format = " {usage}%";
          tooltip-format = "CPU: {usage}%\nLoad: {load}";
          on-click = "kitty -e btop";
        };

        memory = {
          interval = 5;
          format = " {percentage}%";
          tooltip-format = "RAM: {used:0.1f}G / {total:0.1f}G";
          on-click = "kitty -e btop";
        };

        temperature = {
          critical-threshold = 80;
          interval = 5;
          format = "{icon} {temperatureC}°C";
          format-critical = "󰸁 {temperatureC}°C";
          format-icons = [ "" "" "" "" "" ];
          tooltip-format = "CPU temp: {temperatureC}°C";
        };

        battery = {
          states = { warning = 30; critical = 15; };
          format = "{icon} {capacity}%";
          format-charging = "󰂄 {capacity}%";
          format-plugged  = "󰚥 {capacity}%";
          format-icons    = [ "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
          tooltip-format  = "Battery: {capacity}%\nPower: {power}W\nTime remaining: {time}";
        };

        "custom/power-draw" = {
          interval = 5;
          return-type = "json";
          exec = "${powerDrawScript}";
          format = "{}";
        };

        network = {
          format-wifi         = "󰤨 {essid}";
          format-ethernet     = "󰈀 {ipaddr}";
          format-disconnected = "󰤭 Offline";
          tooltip-format-wifi = "{essid}\n{signaldBm} dBm  ↑{bandwidthUpBits} ↓{bandwidthDownBits}";
          tooltip-format-ethernet = "{ifname}: {ipaddr}";
          on-click = "kitty -e nmtui";
        };

        pulseaudio = {
          format       = "{icon} {volume}%";
          format-muted = "󰝟 muted";
          format-icons = {
            default   = [ "󰕿" "󰖀" "󰕾" ];
            headphone = [ "󰋋" ];
            headset   = [ "󰋎" ];
          };
          scroll-step = 2;
          on-click       = "${pkgs.swayosd}/bin/swayosd-client --output-volume mute-toggle";
          on-click-right = "kitty -e pulsemixer";
          tooltip-format = "{desc}\nVolume: {volume}%";
        };

        backlight = {
          format = "{icon} {percent}%";
          format-icons = [ "󰃞" "󰃟" "󰃠" ];
          on-click       = "${brightnessScript} up";
          on-click-right = "kitty --hold -e ${pkgs.brightnessctl}/bin/brightnessctl";
          on-scroll-up   = "${pkgs.swayosd}/bin/swayosd-client --brightness raise";
          on-scroll-down = "${pkgs.swayosd}/bin/swayosd-client --brightness lower";
          tooltip-format = "Brightness: {percent}%";
        };

        "custom/brightness" = {
          interval = 5;
          return-type = "json";
          exec = "${brightnessStatusScript}";
          format = "󰃠  {}";
          on-scroll-up   = "${brightnessScript} up";
          on-scroll-down = "${brightnessScript} down";
          on-click       = "${brightnessScript} up";
        };

        # SwayOSD handles internal brightness natively — the custom/brightness
        # module with ddcutil is only shown on external monitors (see modules-right).

        bluetooth = {
          format           = "󰂯 {status}";
          format-connected = "󰂱 {device_alias}";
          format-off       = "󰂲";
          tooltip-format   = "{controller_alias}\n{controller_address}\n\n{num_connections} connected";
          on-click         = "blueman-manager";
        };

        "power-profiles-daemon" = {
          format = "{icon}";
          tooltip-format = "Power profile: {profile}\nDriver: {driver}";
          format-icons = {
            default       = "󰾅";
            performance   = "󰓅";
            balanced      = "󰾅";
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
          on-click       = "swaync-client -t -sw";
          on-click-right = "swaync-client -d -sw";
          tooltip = false;
        };

        "custom/power" = {
          format = "⏻";
          tooltip = false;
          on-click = "${powerMenu}";
        };

        tray = {
          icon-size = 16;
          spacing   = 8;
        };
      };

      # ── Shared layout (same module list on every output) ──────────────────
      sharedLayout = {
        layer    = "top";
        position = "top";
        spacing  = 0;
        fixed-center = true;
        margin-left   = 12;
        margin-right  = 12;
        margin-bottom = 0;
        modules-left   = [ "hyprland/workspaces" "hyprland/window" ];
        modules-center = [ "clock" ];
        modules-right  = [
          "custom/media"
          "cpu" "memory" "temperature"
          "pulseaudio" "backlight" "battery" "custom/power-draw"
          "network" "custom/tailscale" "bluetooth" "power-profiles-daemon"
          "custom/notification" "tray" "custom/power"
        ];
      };
    in
    {
      enable = true;
      settings = [
        # Laptop built-in display — larger
        (sharedLayout // sharedModules // {
          output    = "eDP-1";
          height    = 42;
          margin-top = 8;
        })
        # External monitors — compact (no backlight: /sys/class/backlight is internal-only)
        (sharedLayout // sharedModules // {
          output    = "!eDP-1";
          height    = 34;
          margin-top = 6;
          modules-right = [
            "custom/media"
            "cpu" "memory" "temperature"
            "pulseaudio" "custom/brightness" "battery" "custom/power-draw"
            "network" "custom/tailscale" "bluetooth" "power-profiles-daemon"
            "custom/notification" "tray" "custom/power"
          ];
        })
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
        padding: 2px 18px 0 10px;
      }

      /* ── Shared right-module padding ── */
      #cpu,
      #memory,
      #temperature,
      #network,
      #pulseaudio,
      #backlight,
      #bluetooth,
      #power-profiles-daemon,
      #custom-media,
      #custom-tailscale {
        padding: 0 10px;
      }

      /* battery + power-draw are one visual unit — no gap between them */
      #battery          { padding: 0 2px 0 10px; }
      #custom-power-draw { padding: 0 10px 0 2px; }

      /* ── Module accent colours ── */
      #custom-media        { color: #50fa7b; }
      #custom-media.Paused { color: #6272a4; }

      #cpu    { color: #ff79c6; }
      #memory { color: #bd93f9; }

      #temperature          { color: #ffb86c; }
      #temperature.critical { color: #ff5555; }

      #pulseaudio       { color: #bd93f9; }
      #pulseaudio.muted { color: #6272a4; }

      #backlight,
      #custom-brightness { color: #f1fa8c; }

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
        padding: 0 10px;
        color: #f8f8f2;
      }
      #custom-notification.dnd {
        color: #6272a4;
      }

      /* ── Power button ── */
      #custom-power {
        padding: 0 12px;
        color: #ff5555;
        font-size: 16px;
      }
      #custom-power:hover {
        color: #ff8080;
      }

      /* ── Tray ── */
      #tray {
        padding: 0 6px;
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
        padding: 0 10px;
      }
      window#waybar:not(.eDP-1) #battery           { padding: 0 2px 0 8px; }
      window#waybar:not(.eDP-1) #custom-power-draw  { padding: 0 8px 0 2px; }

      window#waybar:not(.eDP-1) #cpu,
      window#waybar:not(.eDP-1) #memory,
      window#waybar:not(.eDP-1) #temperature,
      window#waybar:not(.eDP-1) #network,
      window#waybar:not(.eDP-1) #pulseaudio,
      window#waybar:not(.eDP-1) #backlight,
      window#waybar:not(.eDP-1) #custom-brightness,
      window#waybar:not(.eDP-1) #bluetooth,
      window#waybar:not(.eDP-1) #power-profiles-daemon,
      window#waybar:not(.eDP-1) #custom-media,
      window#waybar:not(.eDP-1) #custom-tailscale,
      window#waybar:not(.eDP-1) #custom-notification {
        padding: 0 8px;
      }
    '';
  };

  # ─── Hyprland ─────────────────────────────────────────────────────────────────
  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = true;
    settings = {
      monitor = [
        # Laptop screen: always below any other monitor (auto-down is dynamic)
        "eDP-1,preferred,auto-down,1"
        # Any external monitor: top-left corner, preferred resolution
        ",preferred,0x0,1"
      ];

      exec-once = [
        "hyprlock"
        "swww-daemon"
        "variety"
        "waybar"
        "wl-paste --type text --watch cliphist store"
        "wl-paste --type image --watch cliphist store"
      ];

      env = [
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
        "TERMINAL,kitty"
        "AQ_MGPU_NO_EXPLICIT,1" # Workaround for eglDupNativeFenceFDANDROID crash on AMD Phoenix iGPU (#9746)
        "AQ_NO_ATOMIC,1"        # Disable atomic modesetting to prevent GPU fence crashes
      ];

      input = {
        kb_layout = "de";
        kb_variant = "";
        follow_mouse = 1;
        sensitivity = 0;
        touchpad = {
          natural_scroll = true;
          disable_while_typing = true;
        };
      };

      cursor = {
        no_hardware_cursors = true;
        inactive_timeout = 0;
      };

      general = {
        gaps_in  = 5;
        gaps_out = 10;
        border_size = 2;
        "col.active_border"   = "rgba(33ccffee) rgba(00ff99ee) 45deg";
        "col.inactive_border" = "rgba(595959aa)";
        layout = "dwindle";
      };

      decoration = {
        rounding = 8;
        blur = {
          enabled = true;
          size    = 3;
          passes  = 1;
        };
        shadow = {
          enabled = true;
          range   = 4;
          render_power = 3;
        };
      };

      animations = {
        enabled = true;
        bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";
        animation = [
          "windows, 1, 7, myBezier"
          "windowsOut, 1, 7, default, popin 80%"
          "border, 1, 10, default"
          "fade, 1, 7, default"
          "workspaces, 1, 6, default"
          "layersIn, 1, 5, default, fade"
          "layersOut, 1, 5, default, fade"
        ];
      };

      misc = {
        disable_hyprland_logo    = true;
        disable_splash_rendering = true;
        force_default_wallpaper  = 0;
      };

      dwindle = {
        pseudotile    = true;
        preserve_split = true;
      };

      windowrule = [
        "float on, match:class ^(floating-calendar)$"
        "size 800 600, match:class ^(floating-calendar)$"
        "center on, match:class ^(floating-calendar)$"

        "float on, match:class ^(com.gabm.satty)$"
        "size 60% 70%, match:class ^(com.gabm.satty)$"
        "center on, match:class ^(com.gabm.satty)$"
      ];

      layerrules = [
        "noanim, fuzzel"
      ];

      "$mod" = "SUPER";

      bind = [
        "$mod, Q, exec, kitty"
        "$mod, C, killactive,"
        "$mod, M, exit,"
        "$mod, E, exec, nemo"
        "$mod, V, exec, cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"
        "$mod, R, exec, fuzzel"
        "$mod, P, pseudo,"
        "$mod, O, togglesplit,"

        "$mod, B,       exec, zen-browser"
        "$mod SHIFT, D, exec, discord"
        "$mod SHIFT, C, exec, code"
        "$mod SHIFT, T, exec, kitty termscp"
        "$mod SHIFT, M, exec, wdisplays"

        # Screenshots: grim → save + clipboard + notification (click to edit in satty)
        ''$mod, S,       exec, bash -c 'F=~/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png; mkdir -p ~/Pictures/Screenshots; grim -g "$(slurp)" "$F" && wl-copy < "$F" && { A=$(notify-send -a "Screenshot" -i "$F" "Screenshot saved" "$F" --action=default=Open) && [ "$A" = "default" ] && satty -f "$F"; } &' ''
        ''$mod SHIFT, S, exec, bash -c 'F=~/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png; mkdir -p ~/Pictures/Screenshots; grim "$F" && wl-copy < "$F" && { A=$(notify-send -a "Screenshot" -i "$F" "Screenshot saved" "$F" --action=default=Open) && [ "$A" = "default" ] && satty -f "$F"; } &' ''
        ''$mod ALT, S,   exec, bash -c 'F=~/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png; mkdir -p ~/Pictures/Screenshots; grim -g "$(hyprctl -j activewindow | jq -r '\"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\"')" "$F" && wl-copy < "$F" && { A=$(notify-send -a "Screenshot" -i "$F" "Screenshot saved" "$F" --action=default=Open) && [ "$A" = "default" ] && satty -f "$F"; } &' ''

        '', PRINT,       exec, bash -c 'F=~/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png; mkdir -p ~/Pictures/Screenshots; grim -g "$(slurp)" "$F" && wl-copy < "$F" && { A=$(notify-send -a "Screenshot" -i "$F" "Screenshot saved" "$F" --action=default=Open) && [ "$A" = "default" ] && satty -f "$F"; } &' ''
        ''$mod, PRINT,   exec, bash -c 'F=~/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png; mkdir -p ~/Pictures/Screenshots; grim "$F" && wl-copy < "$F" && { A=$(notify-send -a "Screenshot" -i "$F" "Screenshot saved" "$F" --action=default=Open) && [ "$A" = "default" ] && satty -f "$F"; } &' ''
        ''$mod SHIFT, PRINT, exec, bash -c 'F=~/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png; mkdir -p ~/Pictures/Screenshots; grim -g "$(hyprctl -j activewindow | jq -r '\"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\"')" "$F" && wl-copy < "$F" && { A=$(notify-send -a "Screenshot" -i "$F" "Screenshot saved" "$F" --action=default=Open) && [ "$A" = "default" ] && satty -f "$F"; } &' ''

        "$mod, X, togglefloating,"
        "$mod, Period, exec, bemoji -t"

        "$mod, F, fullscreen, 0"
        "$mod SHIFT, F, fullscreen, 1"
        "$mod, TAB, workspace, previous"
        "$mod, G, togglespecialworkspace, magic"
        "$mod SHIFT, G, movetoworkspace, special:magic"

        "$mod, L, exec, hyprlock"
        "$mod SHIFT, V, centerwindow,"

        "$mod, left,  movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up,    movefocus, u"
        "$mod, down,  movefocus, d"
        "$mod, H, movefocus, l"
        "$mod, J, movefocus, d"
        "$mod, K, movefocus, u"
        "$mod, L, movefocus, r"

        "$mod SHIFT, left,  movewindow, l"
        "$mod SHIFT, right, movewindow, r"
        "$mod SHIFT, up,    movewindow, u"
        "$mod SHIFT, down,  movewindow, d"
        "$mod SHIFT, H, movewindow, l"
        "$mod SHIFT, J, movewindow, d"
        "$mod SHIFT, K, movewindow, u"
        "$mod SHIFT, L, movewindow, r"

        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod, 0, workspace, 10"

        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        "$mod SHIFT, 0, movetoworkspace, 10"

        "$mod, mouse_down, workspace, e+1"
        "$mod, mouse_up,   workspace, e-1"
      ];

      binde = [
        "$mod CTRL, left,  resizeactive, -20 0"
        "$mod CTRL, right, resizeactive, 20 0"
        "$mod CTRL, up,    resizeactive, 0 -20"
        "$mod CTRL, down,  resizeactive, 0 20"
        "$mod CTRL, H, resizeactive, -20 0"
        "$mod CTRL, J, resizeactive, 0 20"
        "$mod CTRL, K, resizeactive, 0 -20"
        "$mod CTRL, L, resizeactive, 20 0"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      bindel = [
        ", XF86AudioRaiseVolume, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume raise"
        ", XF86AudioLowerVolume, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume lower"
        ", XF86MonBrightnessUp, exec, ${pkgs.swayosd}/bin/swayosd-client --brightness raise"
        ", XF86MonBrightnessDown, exec, ${pkgs.swayosd}/bin/swayosd-client --brightness lower"
      ];
      bindl = [
        ", XF86AudioMute, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume mute-toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"
      ];

    };
  };


  # ─── SwayOSD (on-screen display for volume/brightness) ────────────────────────
  services.swayosd = {
    enable = true;
    topMargin = 0.85;
    stylePath =
      let
        css = pkgs.writeText "swayosd-dracula.css" ''
          window#osd {
            padding: 12px 20px;
            border-radius: 14px;
            border: 2px solid rgba(189, 147, 249, 0.6);
            background-color: rgba(40, 42, 54, 0.92);
          }
          #container {
            margin: 6px;
          }
          image, label {
            color: #f8f8f2;
          }
          progressbar:disabled,
          image:disabled {
            opacity: 0.5;
          }
          progressbar {
            min-height: 6px;
            min-width: 0;
            border-radius: 999px;
            background: transparent;
            border: none;
          }
          trough {
            min-height: 6px;
            min-width: 0;
            border-radius: 999px;
            background-color: #44475a;
            border: none;
          }
          progress {
            min-height: 6px;
            min-width: 0;
            border-radius: 999px;
            background-color: #bd93f9;
            border: none;
          }
        '';
      in "${css}";
  };

  # ─── SwayNC (notification center) ──────────────────────────────────────────
  services.swaync = {
    enable = true;

    settings = {
      positionX = "right";
      positionY = "top";
      layer = "overlay";
      control-center-layer = "top";
      cssPriority = "application";

      notification-window-width = 360;
      notification-icon-size = 48;
      notification-body-image-height = 100;
      notification-body-image-width = 200;

      timeout = 8;
      timeout-low = 4;
      timeout-critical = 0;

      fit-to-screen = true;
      control-center-width = 400;
      control-center-height = 600;
      control-center-margin-top = 10;
      control-center-margin-bottom = 10;
      control-center-margin-right = 10;

      hide-on-clear = true;
      hide-on-action = true;

      widgets = [
        "title"
        "dnd"
        "notifications"
      ];

      widget-config = {
        title = {
          text = "Notifications";
          clear-all-button = true;
          button-text = "Clear All";
        };
        dnd = {
          text = "Do Not Disturb";
        };
      };
    };

    style = ''
      @define-color bg      rgba(40, 42, 54, 0.95);
      @define-color bg-solid #282a36;
      @define-color fg      #f8f8f2;
      @define-color comment #6272a4;
      @define-color purple  #bd93f9;
      @define-color pink    #ff79c6;
      @define-color cyan    #8be9fd;
      @define-color green   #50fa7b;
      @define-color red     #ff5555;
      @define-color yellow  #f1fa8c;
      @define-color orange  #ffb86c;
      @define-color current #44475a;

      * {
        font-family: "JetBrainsMono Nerd Font", "JetBrains Mono", monospace;
        font-size: 13px;
      }

      /* ── Notification popups ── */

      .notification-row {
        outline: none;
        background: transparent;
      }

      .notification-row:focus,
      .notification-row:hover {
        background: transparent;
      }

      .notification-row .notification-background {
        background: transparent;
      }

      .notification-group {
        background: transparent;
      }

      .notification-group:focus,
      .notification-group:hover {
        background: transparent;
      }

      .notification-group .notification-group-headers,
      .notification-group .notification-group-buttons {
        background: transparent;
      }

      .notification {
        background: @bg;
        border-radius: 12px;
        border: 2px solid @comment;
        margin: 4px 10px;
        padding: 0;
        box-shadow: 0 2px 12px rgba(0, 0, 0, 0.4);
      }

      .notification-content {
        padding: 10px 14px;
        color: @fg;
      }

      .notification .summary {
        font-weight: bold;
        color: @fg;
      }

      .notification .body {
        color: @comment;
      }

      .notification .time {
        color: @comment;
        font-size: 11px;
      }

      .notification:hover {
        border-color: @purple;
      }

      .critical .notification {
        border-color: @red;
      }

      .low .notification {
        border-color: @current;
      }

      /* ── Close button ── */
      .close-button {
        background: @current;
        color: @fg;
        border-radius: 6px;
        padding: 2px 6px;
        margin: 6px;
        border: none;
      }
      .close-button:hover {
        background: @red;
      }

      /* ── Notification actions ── */
      .notification-action {
        background: @current;
        color: @fg;
        border-radius: 8px;
        border: none;
        margin: 4px;
        padding: 6px 12px;
      }
      .notification-action:hover {
        background: @purple;
        color: @bg-solid;
      }

      /* ── Control center ── */
      .control-center {
        background: @bg;
        border-radius: 14px;
        border: 2px solid rgba(98, 114, 164, 0.5);
        box-shadow: 0 4px 20px rgba(0, 0, 0, 0.5);
        margin: 8px;
        padding: 10px;
      }

      /* ── Title widget ── */
      .widget-title {
        color: @fg;
        font-weight: bold;
        font-size: 15px;
        margin: 6px 8px;
      }
      .widget-title > button {
        background: @current;
        color: @fg;
        border-radius: 8px;
        border: none;
        padding: 4px 12px;
        font-size: 12px;
      }
      .widget-title > button:hover {
        background: @red;
      }

      /* ── DND toggle ── */
      .widget-dnd {
        margin: 4px 8px;
        color: @fg;
      }
      .widget-dnd > switch {
        background: @current;
        border-radius: 12px;
        border: none;
      }
      .widget-dnd > switch:checked {
        background: @purple;
      }
      .widget-dnd > switch slider {
        background: @fg;
        border-radius: 10px;
        min-width: 16px;
        min-height: 16px;
      }

      /* ── Notifications in control center ── */
      .control-center .notification {
        margin: 4px 2px;
      }

      /* ── Progress bars (volume/brightness from apps) ── */
      progressbar {
        min-height: 6px;
      }
      trough {
        background: @current;
        border-radius: 999px;
        min-height: 6px;
      }
      progress {
        background: @purple;
        border-radius: 999px;
        min-height: 6px;
      }
    '';
  };


  # ─── Cursor Theme ─────────────────────────────────────────────────────────────
  home.pointerCursor = {
    name = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size = 24;
    gtk.enable = true;
  };

  # ─── Hyprlock ─────────────────────────────────────────────────────────────────
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        grace = 3;
      };

      background = [{
        path = "${config.home.homeDirectory}/.current-wallpaper";
        crossfade_time = 1.5;
      }];

      # ── Blurred box behind widgets ──────────────────────────────────────
      shape = [{
        size = "460, 440";
        color = "rgba(40, 42, 54, 0.55)";
        rounding = 24;
        blur_size = 6;
        blur_passes = 3;
        noise = 0.01;
        border_size = 2;
        border_color = "rgba(189, 147, 249, 0.25)";
        position = "0, 15";
        halign = "center";
        valign = "center";
      }];

      # ── Clock ──────────────────────────────────────────────────────────
      label = [
        {
          text = ''cmd[update:1000] echo "$(date +"%H:%M")"'';
          color = "rgba(248, 248, 242, 1.0)";
          font_size = 88;
          font_family = "JetBrains Mono ExtraBold";
          position = "0, 130";
          halign = "center";
          valign = "center";
          shadow_passes = 3;
          shadow_size = 6;
          shadow_color = "rgba(0, 0, 0, 0.5)";
        }
        # ── Date ─────────────────────────────────────────────────────────
        {
          text = ''cmd[update:60000] echo "$(LC_TIME=en_US.UTF-8 date +"%A, %d %B %Y")"'';
          color = "rgba(189, 147, 249, 1.0)";
          font_size = 16;
          font_family = "JetBrains Mono";
          position = "0, 40";
          halign = "center";
          valign = "center";
          shadow_passes = 2;
          shadow_size = 3;
          shadow_color = "rgba(0, 0, 0, 0.4)";
        }
        # ── User ─────────────────────────────────────────────────────────
        {
          text = "󰌾   $USER";
          color = "rgba(98, 114, 164, 1.0)";
          font_size = 13;
          font_family = "JetBrainsMono Nerd Font";
          position = "0, -40";
          halign = "center";
          valign = "center";
        }
      ];

      # ── Fingerprint ─────────────────────────────────────────────────────
      auth = {
        fingerprint = {
          enabled = true;
          ready_message = "Scan fingerprint to unlock";
          present_message = "Scanning…";
        };
      };

      # ── Password field ─────────────────────────────────────────────────
      input-field = [{
        size = "340, 50";
        outline_thickness = 2;
        dots_size = 0.22;
        dots_spacing = 0.35;
        outer_color = "rgb(189, 147, 249)";
        inner_color = "rgb(68, 71, 90)";
        font_color = "rgb(248, 248, 242)";
        check_color = "rgb(80, 250, 123)";
        fail_color = "rgb(255, 85, 85)";
        capslock_color = "rgb(241, 250, 140)";
        rounding = 12;
        fade_on_empty = false;
        placeholder_text = ''<span foreground="##6272a4">  Password</span>'';
        fail_text = ''<i>$FAIL  <b>($ATTEMPTS)</b></i>'';
        position = "0, -110";
        halign = "center";
        valign = "center";
      }];
    };
  };

  # ─── Hypridle ─────────────────────────────────────────────────────────────────
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        {
          timeout = 300;
          on-timeout = "brightnessctl -s set 30%";
          on-resume = "brightnessctl -r";
        }
        {
          timeout = 600;
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 900;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        {
          timeout = 1800; # 30 min — suspend-then-hibernate when idle
          on-timeout = "systemctl suspend-then-hibernate";
        }
      ];
    };
  };

  # ─── Kanshi (display profiles) ───────────────────────────────────────────────
  services.kanshi = {
    enable = true;
    settings = [
      # Laptop screen only
      {
        profile.name = "laptop-only";
        profile.outputs = [{
          criteria = "eDP-1";
          status   = "enable";
        }];
      }

      # Any external monitor connected — Hyprland's auto-down rule places
      # eDP-1 below whatever external is active, regardless of its resolution.
      {
        profile.name = "docked";
        profile.outputs = [
          { criteria = "*";     status = "enable"; }
          { criteria = "eDP-1"; status = "enable"; }
        ];
      }
    ];
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

  # ─── GTK ──────────────────────────────────────────────────────────────────────
  gtk = {
    enable = true;
    theme = {
      name    = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name    = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };
}
