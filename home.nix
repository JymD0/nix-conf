{ config, pkgs, lib, ... }:

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
  home.packages = with pkgs; [
    # Screenshots
    grim
    slurp
    grimblast

    # QoL tools
    cliphist
    fuzzel
    wofi
    waybar          # status bar

    # File manager
    nemo

    # Notifications
    libnotify

    # Display management
    wdisplays       # GUI for managing monitors (position, resolution, scale)
    kanshi          # auto-switch monitor profiles

    # Lock screen
    hyprlock

    # System info
    fastfetch
    btop

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

    # Claude Code (npm install -g @anthropic-ai/claude-code)
    nodejs_22

    # Wallpaper
    swww       # animated wallpaper daemon for Wayland
    waypaper   # GUI frontend for picking / setting wallpapers
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

  # ─── SSH ──────────────────────────────────────────────────────────────────────
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks."*".extraOptions.AddKeysToAgent = "yes";
    matchBlocks = {
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

  programs.starship.enable = true;

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
        kb_layout = "us";
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
        # drop_shadow and shadow_* were replaced by shadow {} block in Hyprland v0.45+
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
        "$mod, J, togglesplit,"

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
        "$mod SHIFT, F, fullscreen, 1"       # maximize (keep gaps/bar)
        "$mod, TAB, workspace, previous"     # quick workspace toggle
        "$mod, S, togglespecialworkspace, magic"
        "$mod SHIFT, S, movetoworkspace, special:magic"

        # Lock screen
        "$mod, L, exec, hyprlock"

        # Center floating window
        "$mod SHIFT, V, centerwindow,"

        # Focus (arrows)
        "$mod, left,  movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up,    movefocus, u"
        "$mod, down,  movefocus, d"

        # Focus (vim keys)
        "$mod, H, movefocus, l"
        "$mod, K, movefocus, u"

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

      # Resize windows (repeatable)
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

      # Volume & brightness (Framework laptop keys)
      bindel = [
        ", XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ", XF86MonBrightnessUp, exec, brightnessctl s 5%+"
        ", XF86MonBrightnessDown, exec, brightnessctl s 5%-"
      ];
      bindl = [
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
      ];
    };
  };

  # ─── Dunst ────────────────────────────────────────────────────────────────────
  services.dunst = {
    enable = true;
    settings = {
      global = {
        # Layout
        width          = 320;
        height         = 200;
        offset         = "15x50";
        origin         = "top-right";
        scale          = 0;
        gap_size        = 6;

        # Progress bar
        progress_bar                  = true;
        progress_bar_height           = 10;
        progress_bar_frame_width      = 1;
        progress_bar_min_width        = 150;
        progress_bar_max_width        = 300;
        progress_bar_corner_radius    = 4;

        # Appearance
        transparency   = 10;
        corner_radius  = 8;
        frame_width    = 2;
        frame_color    = "#bd93f9";   # Dracula purple
        separator_color = "frame";
        separator_height = 2;
        padding        = 10;
        horizontal_padding = 12;
        text_icon_padding  = 8;

        # Typography
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

        # Icons
        icon_theme     = "Adwaita";
        enable_recursive_icon_lookup = true;
        icon_position  = "left";
        min_icon_size  = 32;
        max_icon_size  = 48;

        # History
        sticky_history = true;
        history_length = 20;

        # Misc
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

      # Urgency levels — Dracula palette
      urgency_low = {
        background = "#282a36";   # Dracula background
        foreground = "#f8f8f2";   # Dracula foreground
        frame_color = "#6272a4";  # Dracula comment / muted
        timeout    = 4;
        icon       = "dialog-information";
      };

      urgency_normal = {
        background = "#282a36";
        foreground = "#f8f8f2";
        frame_color = "#bd93f9";  # Dracula purple
        timeout    = 8;
        icon       = "dialog-information";
      };

      urgency_critical = {
        background = "#282a36";
        foreground = "#ff5555";   # Dracula red
        frame_color = "#ff5555";
        timeout    = 0;           # stays until dismissed
        icon       = "dialog-warning";
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
  };
}
