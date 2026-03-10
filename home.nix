{ config, pkgs, lib, hyprland-contrib, claude-code, ... }:

let
  # Smart brightness control: brightnessctl for internal (eDP-1), ddcutil for external monitors
  brightnessScript = pkgs.writeShellScript "brightness-ctl" ''
    ACTION=$1
    STEP=5

    ACTIVE_MON=$(${pkgs.hyprland}/bin/hyprctl activeworkspace -j 2>/dev/null \
      | ${pkgs.jq}/bin/jq -r '.monitor // "eDP-1"')

    if [ "$ACTIVE_MON" = "eDP-1" ] || [ -z "$ACTIVE_MON" ]; then
      case "$ACTION" in
        up)   ${pkgs.brightnessctl}/bin/brightnessctl s "$STEP%+" -q ;;
        down) ${pkgs.brightnessctl}/bin/brightnessctl s "$STEP%-" -q ;;
      esac
      CUR=$(${pkgs.brightnessctl}/bin/brightnessctl g)
      MAX=$(${pkgs.brightnessctl}/bin/brightnessctl m)
      PCT=$(( CUR * 100 / MAX ))
      LABEL="Internal"
    else
      CUR=$(${pkgs.ddcutil}/bin/ddcutil getvcp 10 --brief 2>/dev/null | awk '{print $4}')
      CUR=''${CUR:-50}
      case "$ACTION" in
        up)   NEW=$(( CUR + STEP > 100 ? 100 : CUR + STEP )) ;;
        down) NEW=$(( CUR - STEP < 0 ? 0 : CUR - STEP )) ;;
      esac
      ${pkgs.ddcutil}/bin/ddcutil setvcp 10 "$NEW" 2>/dev/null
      PCT=$NEW
      LABEL="External"
    fi

    ${pkgs.libnotify}/bin/notify-send \
      -h string:x-canonical-private-synchronous:brightness \
      -h "int:value:$PCT" \
      -t 2000 \
      "󰃠 Brightness ($LABEL)" "$PCT%"
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
      *Hibernate*)   systemctl hibernate ;;
      *Reboot*)      systemctl reboot ;;
      *"Shut down"*) systemctl poweroff ;;
    esac
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

  # ─── Fonts ─────────────────────────────────────────────────────────────────────
  fonts.fontconfig.enable = true;

  # ─── Packages ───────────────────────────────────────────────────────────────────
  home.packages = (with pkgs; [
    # Screenshots
    grim
    slurp

    # QoL tools
    cliphist

    # File manager
    nemo

    # Notifications
    libnotify

    # Bluetooth & network (needed by Waybar on-click actions)
    blueman
    networkmanagerapplet

    # Display management
    wdisplays
    kanshi

    # Lock screen
    hyprlock

    # System info
    fastfetch
    btop

    # Audio mixer
    pulsemixer

    # Media control
    playerctl

    # Apps
    discord

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
    waypaper
    variety

    # Calendar
    khal
    vdirsyncer

    # Utilities
    ripgrep
    fd
    jq
    unzip
    p7zip

    # Misc
    xdg-utils
  ]) ++ [
    hyprland-contrib.packages.${pkgs.stdenv.hostPlatform.system}.grimblast
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
      # ─── Variety wallpaper config ───────────────────────────────────────────────
      "variety/variety.conf".text = ''
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
      '';

      # Custom set_wallpaper script using swww
      "variety/scripts/set_wallpaper".source =
        let
          script = pkgs.writeShellScript "variety-set-wallpaper" ''
            if [ -z "$1" ]; then
              exit 1
            fi
            ${pkgs.swww}/bin/swww img "$1" \
              --transition-type fade \
              --transition-duration 1 \
              --transition-fps 60
          '';
        in script;

      # Variety also needs a get_wallpaper script
      "variety/scripts/get_wallpaper".source =
        let
          script = pkgs.writeShellScript "variety-get-wallpaper" ''
            ${pkgs.swww}/bin/swww query | grep -oP 'image: \K.*' | head -1
          '';
        in script;

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

        # Collapse when empty so it doesn't leave a blank gap in the left pill.
        "hyprland/window" = {
          format = "{}";
          max-length = 50;
          separate-outputs = true;
        };

        clock = {
          format     = " {:%H:%M}";
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
          tooltip-format  = "Battery: {capacity}%\nTime remaining: {time}";
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
          on-click       = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          on-click-right = "kitty -e pulsemixer";
          tooltip-format = "{desc}\nVolume: {volume}%";
        };

        backlight = {
          format = "{icon} {percent}%";
          format-icons = [ "󰃞" "󰃟" "󰃠" ];
          on-click       = "${brightnessScript} up";
          on-click-right = "kitty --hold -e ${pkgs.brightnessctl}/bin/brightnessctl";
          on-scroll-up   = "${brightnessScript} up";
          on-scroll-down = "${brightnessScript} down";
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
          exec = ''bash -c 'p=$(dunstctl is-paused 2>/dev/null); n=$(dunstctl count waiting 2>/dev/null || echo 0); [ "$p" = "true" ] && echo "󰪑 DND" || { [ "$n" -gt 0 ] && echo "󰂚 $n" || echo "󰂜"; }' '';
          on-click       = "dunstctl set-paused toggle";
          on-click-right = "dunstctl history-pop";
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
          "pulseaudio" "backlight" "battery"
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
            "pulseaudio" "custom/brightness" "battery"
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
        background: rgba(40, 42, 54, 0.92);
        border-radius: 14px;
        padding: 0 8px;
        margin: 5px 4px;
        box-shadow: 0 2px 12px rgba(0, 0, 0, 0.35);
      }

      /* ── Workspaces ── */
      #workspaces {
        padding: 0 2px;
      }

      #workspaces button {
        padding: 0 10px;
        color: #6272a4;
        background: transparent;
        border-radius: 10px;
        margin: 4px 2px;
        font-weight: bold;
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
        padding: 0;
        margin: 0;
      }

      /* ── Clock ── */
      #clock {
        color: #f8f8f2;
        font-weight: bold;
        font-size: 15px;
        letter-spacing: 0.5px;
        padding: 0 16px;
      }

      /* ── Shared right-module padding ── */
      #cpu,
      #memory,
      #temperature,
      #battery,
      #network,
      #pulseaudio,
      #backlight,
      #bluetooth,
      #power-profiles-daemon,
      #custom-media,
      #custom-tailscale {
        padding: 0 10px;
      }

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
        padding: 0 8px;
        margin: 3px 1px;
      }
      window#waybar:not(.eDP-1) #custom-power {
        font-size: 14px;
        padding: 0 10px;
      }
      window#waybar:not(.eDP-1) #cpu,
      window#waybar:not(.eDP-1) #memory,
      window#waybar:not(.eDP-1) #temperature,
      window#waybar:not(.eDP-1) #battery,
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
    systemd.enable = false;
    settings = {
      monitor = [
        # Laptop screen: always below any other monitor (auto-down is dynamic)
        "eDP-1,preferred,auto-down,1"
        # Any external monitor: top-left corner, preferred resolution
        ",preferred,0x0,1"
      ];

      exec-once = [
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
        "$mod, V, togglefloating,"
        "$mod, R, exec, fuzzel"
        "$mod, P, pseudo,"
        "$mod, O, togglesplit,"

        "$mod, B,       exec, zen-browser"
        "$mod SHIFT, D, exec, discord"
        "$mod SHIFT, C, exec, code"
        "$mod SHIFT, T, exec, kitty termscp"
        "$mod SHIFT, M, exec, wdisplays"

        ", PRINT,       exec, grimblast copy area"
        "$mod, PRINT,   exec, grimblast copy output"
        "$mod SHIFT, PRINT, exec, grimblast save area ~/Pictures/$(date +%Y-%m-%d_%H-%M-%S).png"

        "$mod, X, exec, cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"

        "$mod, F, fullscreen, 0"
        "$mod SHIFT, F, fullscreen, 1"
        "$mod, TAB, workspace, previous"
        "$mod, S, togglespecialworkspace, magic"
        "$mod SHIFT, S, movetoworkspace, special:magic"

        "$mod ALT, L, exec, hyprlock"
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
        ", XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ", XF86MonBrightnessUp, exec, ${brightnessScript} up"
        ", XF86MonBrightnessDown, exec, ${brightnessScript} down"
      ];
      bindl = [
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"
      ];

    };
  };


  # ─── Dunst ────────────────────────────────────────────────────────────────────
  services.dunst = {
    enable = true;
    settings = {
      global = {
        monitor        = "eDP-1";
        follow         = "none";
        width          = 320;
        height         = 200;
        offset         = "15x50";
        origin         = "top-right";
        scale          = 0;
        gap_size        = 6;

        progress_bar                  = true;
        progress_bar_height           = 10;
        progress_bar_frame_width      = 1;
        progress_bar_min_width        = 150;
        progress_bar_max_width        = 300;
        progress_bar_corner_radius    = 4;

        transparency   = 10;
        corner_radius  = 8;
        frame_width    = 2;
        frame_color    = "#bd93f9";
        separator_color = "frame";
        separator_height = 2;
        padding        = 10;
        horizontal_padding = 12;
        text_icon_padding  = 8;

        font           = "JetBrains Mono 10";
        line_height    = 0;
        markup         = "full";
        format         = "<b>%s</b>\\n%b";
        alignment      = "left";
        vertical_alignment = "center";
        ellipsize      = "middle";
        ignore_newline = false;
        stack_duplicates = true;
        hide_duplicate_count = false;
        show_indicators = true;

        icon_theme     = "Papirus-Dark";
        enable_recursive_icon_lookup = true;
        icon_position  = "left";
        min_icon_size  = 32;
        max_icon_size  = 48;

        sticky_history = true;
        history_length = 20;

        dmenu          = "${pkgs.fuzzel}/bin/fuzzel --dmenu";
        browser        = "${pkgs.xdg-utils}/bin/xdg-open";
        always_run_script = true;
        title          = "Dunst";
        class          = "Dunst";
        ignore_dbusclose = false;
        force_xwayland  = false;
        force_xinerama  = false;
        mouse_left_click   = "close_current";
        mouse_middle_click = "do_action, close_current";
        mouse_right_click  = "close_all";
      };

      urgency_low = {
        background = "#282a36";
        foreground = "#f8f8f2";
        frame_color = "#6272a4";
        timeout    = 4;
        icon       = "dialog-information";
      };

      urgency_normal = {
        background = "#282a36";
        foreground = "#f8f8f2";
        frame_color = "#bd93f9";
        timeout    = 8;
        icon       = "dialog-information";
      };

      urgency_critical = {
        background = "#282a36";
        foreground = "#ff5555";
        frame_color = "#ff5555";
        timeout    = 0;
        icon       = "dialog-warning";
      };
    };
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
        grace = 0;
      };

      background = [{
        color = "rgb(40, 42, 54)";
        blur_passes = 3;
        blur_size = 7;
        noise = 0.012;
        brightness = 0.82;
        vibrancy = 0.17;
      }];

      # ── Clock ──────────────────────────────────────────────────────────
      label = [
        {
          text = ''cmd[update:1000] echo "$(date +"%H:%M")"'';
          color = "rgba(248, 248, 242, 1.0)";
          font_size = 88;
          font_family = "JetBrains Mono ExtraBold";
          position = "0, 200";
          halign = "center";
          valign = "center";
          shadow_passes = 3;
          shadow_size = 6;
          shadow_color = "rgba(0, 0, 0, 0.5)";
        }
        # ── Date ─────────────────────────────────────────────────────────
        {
          text = ''cmd[update:60000] echo "$(date +"%A, %d %B %Y")"'';
          color = "rgba(189, 147, 249, 1.0)";
          font_size = 18;
          font_family = "JetBrains Mono";
          position = "0, 100";
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
          position = "0, -120";
          halign = "center";
          valign = "center";
        }
      ];

      # ── Fingerprint ─────────────────────────────────────────────────────
      fingerprint = {
        enabled = true;
        ready_message = "Scan fingerprint to unlock";
        present_message = "Scanning…";
      };

      # ── Password field ─────────────────────────────────────────────────
      input-field = [{
        size = "320, 52";
        outline_thickness = 2;
        dots_size = 0.22;
        dots_spacing = 0.35;
        outer_color = "rgb(189, 147, 249)";
        inner_color = "rgb(68, 71, 90)";
        font_color = "rgb(248, 248, 242)";
        check_color = "rgb(80, 250, 123)";
        fail_color = "rgb(255, 85, 85)";
        capslock_color = "rgb(241, 250, 140)";
        rounding = 10;
        fade_on_empty = true;
        placeholder_text = ''<span foreground="##6272a4">  Password</span>'';
        fail_text = ''<i>$FAIL  <b>($ATTEMPTS)</b></i>'';
        position = "0, -70";
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
      ];
    };
  };

  # ─── Kanshi (display profiles) ───────────────────────────────────────────────
  services.kanshi = {
    enable = true;
    profiles = {
      # Laptop screen only
      laptop-only = {
        outputs = [{
          criteria = "eDP-1";
          status   = "enable";
        }];
      };

      # Any external monitor connected — Hyprland's auto-down rule places
      # eDP-1 below whatever external is active, regardless of its resolution.
      docked = {
        outputs = [
          { criteria = "*";     status = "enable"; }
          { criteria = "eDP-1"; status = "enable"; }
        ];
      };
    };
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
