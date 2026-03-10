{ config, pkgs, lib, hyprland-contrib, claude-code, ... }:

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
    wdisplays       # GUI for managing monitors (position, resolution, scale)
    kanshi          # auto-switch monitor profiles

    # Lock screen
    hyprlock

    # System info
    fastfetch
    btop

    # Audio mixer (needed by Waybar pulseaudio on-click-right)
    pulsemixer

    # Media control
    playerctl

    # Apps
    discord

    # Fonts
    noto-fonts-color-emoji
    jetbrains-mono
    font-awesome          # icons for Waybar
    nerd-fonts.jetbrains-mono  # Nerd Font variant with extra glyphs

    # SSH & File Transfer
    termscp
    sshpass

    # Wallpaper
    swww       # animated wallpaper daemon for Wayland
    waypaper   # GUI frontend for picking / setting wallpapers

    # Utilities
    ripgrep
    fd
    jq
    unzip
    p7zip

    # Misc
    xdg-utils
  ]) ++ [
    # Flake inputs (outside `with pkgs` scope)
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

      # Dracula colors
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
        icon-theme = "Adwaita";
        icons-enabled = true;
        terminal = "kitty";
        layer = "overlay";
        exit-on-keyboard-focus-loss = true;
        width = 35;          # columns
        lines = 10;
        horizontal-pad = 16;
        vertical-pad = 12;
        inner-pad = 6;
        border-radius = 10; # rounded corners matching Hyprland rounding
      };
      colors = {
        # Dracula palette — format is RRGGBBaa
        background = "282a36ee"; # semi-transparent dark
        text       = "f8f8f2ff";
        match      = "bd93f9ff"; # purple highlight for matched chars
        selection  = "44475aff"; # selected row background
        selection-text = "f8f8f2ff";
        selection-match = "ff79c6ff"; # pink for matched chars in selection
        border     = "bd93f9ff"; # purple border
      };
      border = {
        width = 2;
        radius = 10;
      };
    };
  };

  # ─── SSH ──────────────────────────────────────────────────────────────────────
  programs.ssh = {
    enable = true;
    matchBlocks = {
      "*" = {
        extraOptions = {
          "AddKeysToAgent" = "yes";
        };
      };
      # Add your SSH hosts here, e.g.:
      # "homelab" = {
      #   hostname = "192.168.1.100";
      #   user = "admin";
      #   identityFile = "~/.ssh/id_ed25519";
      # };
      # "vps" = {
      #   hostname = "your-vps.example.com";
      #   user = "root";
      # };
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
    userName = "Your Name";
    userEmail = "your.email@example.com";
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
  programs.waybar = {
    enable = true;
    settings = [{
      layer  = "top";
      position = "top";
      height = 32;
      spacing = 4;

      modules-left   = [ "hyprland/workspaces" "hyprland/window" ];
      modules-center = [ "clock" ];
      modules-right  = [
        "pulseaudio"
        "backlight"
        "battery"
        "network"
        "bluetooth"
        "tray"
      ];

      "hyprland/workspaces" = {
        format = "{icon}";
        format-icons = {
          "1" = "1"; "2" = "2"; "3" = "3"; "4" = "4"; "5" = "5";
          "6" = "6"; "7" = "7"; "8" = "8"; "9" = "9"; "10" = "10";
          urgent = "";
          active = "";
          default = "";
        };
        persistent-workspaces = {};
      };

      "hyprland/window" = {
        format = "{}";
        max-length = 50;
      };

      clock = {
        format = " {:%H:%M}";
        format-alt = " {:%A, %d %B %Y}";
        tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
      };

      battery = {
        states = { warning = 30; critical = 15; };
        format = "{icon} {capacity}%";
        format-charging    = " {capacity}%";
        format-plugged     = " {capacity}%";
        format-warning     = " {capacity}%";
        format-critical    = " {capacity}%";
        format-icons       = [ "" "" "" "" "" ];
      };

      network = {
        format-wifi         = " {essid}";
        format-ethernet     = " {ipaddr}";
        format-disconnected = "⚠ Disconnected";
        tooltip-format      = "{ifname}: {ipaddr}\nSignal: {signaldBm} dBm";
        on-click            = "kitty -e nmtui";
      };

      pulseaudio = {
        format        = "{icon} {volume}%";
        format-muted  = " muted";
        format-icons  = { default = [ "" "" "" ]; };
        on-click      = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        on-click-right = "kitty -e pulsemixer";
      };

      backlight = {
        format = "{icon} {percent}%";
        format-icons = [ "" "" "" "" "" "" "" "" "" ];
        on-scroll-up   = "brightnessctl s 5%+";
        on-scroll-down = "brightnessctl s 5%-";
      };

      bluetooth = {
        format          = " {status}";
        format-connected = " {device_alias}";
        format-off      = "";
        tooltip-format  = "{controller_alias}\t{controller_address}\n\n{num_connections} connected";
        on-click        = "blueman-manager";
      };

      tray = {
        spacing = 8;
      };
    }];

    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font", "Font Awesome 6 Free", "Font Awesome 6 Brands", monospace;
        font-size: 13px;
        min-height: 0;
      }

      window#waybar {
        background-color: rgba(40, 42, 54, 0.92);
        color: #f8f8f2;
        border-bottom: 2px solid #bd93f9;
      }

      .modules-left, .modules-center, .modules-right {
        padding: 0 8px;
      }

      #workspaces button {
        padding: 0 6px;
        color: #6272a4;
        background: transparent;
        border: none;
        border-radius: 4px;
      }
      #workspaces button.active {
        color: #f8f8f2;
        background-color: #44475a;
      }
      #workspaces button.urgent {
        color: #ff5555;
      }

      #clock {
        color: #8be9fd;
        font-weight: bold;
      }

      #battery {
        color: #50fa7b;
      }
      #battery.warning {
        color: #f1fa8c;
      }
      #battery.critical {
        color: #ff5555;
        animation: blink 0.5s steps(1) infinite;
      }
      @keyframes blink {
        to { color: #f8f8f2; }
      }

      #network {
        color: #8be9fd;
      }
      #network.disconnected {
        color: #ff5555;
      }

      #pulseaudio {
        color: #bd93f9;
      }
      #pulseaudio.muted {
        color: #6272a4;
      }

      #backlight {
        color: #f1fa8c;
      }

      #bluetooth {
        color: #8be9fd;
      }
      #bluetooth.off {
        color: #6272a4;
      }

      #tray {
        padding: 0 4px;
      }

      tooltip {
        background-color: #282a36;
        border: 1px solid #44475a;
        border-radius: 6px;
        color: #f8f8f2;
      }
    '';
  };

  # ─── Hyprland ─────────────────────────────────────────────────────────────────
  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = false; # required when programs.hyprland.withUWSM = true
    settings = {
      monitor = ",preferred,auto,1";

      exec-once = [
        "swww-daemon"
        "waypaper --restore"  # restore last wallpaper on login
        "waybar"
        "kanshi"
        "wl-paste --type text --watch cliphist store"
        "wl-paste --type image --watch cliphist store"
      ];

      env = [
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
        "TERMINAL,kitty"
      ];

      input = {
        kb_layout = "de";  # matches system-wide XKB layout
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

      dwindle = {
        pseudotile    = true;
        preserve_split = true;
      };

      "$mod" = "SUPER";

      bind = [
        # Core
        "$mod, Q, exec, kitty"
        "$mod, C, killactive,"
        "$mod, M, exit,"
        "$mod, E, exec, nemo"
        "$mod, V, togglefloating,"
        "$mod, R, exec, fuzzel"
        "$mod, P, pseudo,"
        "$mod, O, togglesplit,"

        # Apps
        "$mod, B,       exec, zen-browser"
        "$mod SHIFT, D, exec, discord"
        "$mod SHIFT, C, exec, code"
        "$mod SHIFT, T, exec, kitty termscp"
        "$mod SHIFT, M, exec, wdisplays"

        # Screenshots
        ", PRINT,       exec, grimblast copy area"
        "$mod, PRINT,   exec, grimblast copy output"
        "$mod SHIFT, PRINT, exec, grimblast save area ~/Pictures/$(date +%Y-%m-%d_%H-%M-%S).png"

        # Clipboard history
        "$mod, X, exec, cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"

        # Fullscreen & layout
        "$mod, F, fullscreen, 0"
        "$mod SHIFT, F, fullscreen, 1"
        "$mod, TAB, workspace, previous"
        "$mod, S, togglespecialworkspace, magic"
        "$mod SHIFT, S, movetoworkspace, special:magic"

        # Lock screen
        "$mod ALT, L, exec, hyprlock"

        # Center floating window
        "$mod SHIFT, V, centerwindow,"

        # Focus (arrows)
        "$mod, left,  movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up,    movefocus, u"
        "$mod, down,  movefocus, d"

        # Focus (vim keys)
        "$mod, H, movefocus, l"
        "$mod, J, movefocus, d"
        "$mod, K, movefocus, u"
        "$mod, L, movefocus, r"

        # Move windows
        "$mod SHIFT, left,  movewindow, l"
        "$mod SHIFT, right, movewindow, r"
        "$mod SHIFT, up,    movewindow, u"
        "$mod SHIFT, down,  movewindow, d"
        "$mod SHIFT, H, movewindow, l"
        "$mod SHIFT, J, movewindow, d"
        "$mod SHIFT, K, movewindow, u"
        "$mod SHIFT, L, movewindow, r"

        # Workspaces
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

        # Move to workspace
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

        # Scroll workspaces
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
        ", XF86MonBrightnessUp, exec, brightnessctl s 5%+"
        ", XF86MonBrightnessDown, exec, brightnessctl s 5%-"
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

        icon_theme     = "Adwaita";
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

  # ─── Cursor Theme ────────────────────────────────────────────────────────────
  home.pointerCursor = {
    name = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size = 24;
    gtk.enable = true;
  };

  # ─── Hyprlock ───────────────────────────────────────────────────────────────
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        grace = 5;
      };
      background = [{
        color = "rgb(40, 42, 54)";
        blur_passes = 2;
        blur_size = 5;
      }];
      input-field = [{
        size = "250, 50";
        outline_thickness = 2;
        dots_size = 0.25;
        dots_spacing = 0.3;
        outer_color = "rgb(189, 147, 249)";
        inner_color = "rgb(68, 71, 90)";
        font_color = "rgb(248, 248, 242)";
        fade_on_empty = true;
        placeholder_text = "<i>Password...</i>";
        fail_color = "rgb(255, 85, 85)";
        fail_text = "<i>$FAIL <b>($ATTEMPTS)</b></i>";
        position = "0, -20";
        halign = "center";
        valign = "center";
      }];
    };
  };

  # ─── Hypridle ───────────────────────────────────────────────────────────────
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        # Dim screen after 5 minutes
        {
          timeout = 300;
          on-timeout = "brightnessctl -s set 30%";
          on-resume = "brightnessctl -r";
        }
        # Lock screen after 10 minutes
        {
          timeout = 600;
          on-timeout = "loginctl lock-session";
        }
        # Turn off display after 15 minutes
        {
          timeout = 900;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };

  # ─── GTK ──────────────────────────────────────────────────────────────────────
  gtk = {
    enable = true;
    theme = {
      name    = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
  };
}
