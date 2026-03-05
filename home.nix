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

    # Shell
    starship

    # File manager
    nemo

    # Notifications
    dunst
    libnotify

    # System info
    fastfetch
    btop

    # Apps
    discord

    # Fonts
    noto-fonts-color-emoji
    jetbrains-mono

    # SSH & File Transfer
    termscp
    sshpass

    # Claude Code dependency
    nodejs_22
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
    extraConfig = ''AddKeysToAgent yes'';
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

  # ─── Git ──────────────────────────────────────────────────────────────────────
  programs.git = {
    enable = true;
    userName  = "Your Name";
    userEmail = "your.email@example.com";
  };

  # ─── Bash ─────────────────────────────────────────────────────────────────────
  programs.bash = {
    enable = true;
    shellAliases = {
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#yourHostname";
      update  = "cd /etc/nixos && sudo nix flake update && sudo nixos-rebuild switch --flake .#yourHostname";
      scpget  = "termscp";
    };
  };

  programs.starship.enable = true;

  # ─── Hyprland ─────────────────────────────────────────────────────────────────
  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      monitor = ",preferred,auto,1";

      exec-once = [
        "wl-paste --type text --watch cliphist store"
        "wl-paste --type image --watch cliphist store"
        "dunst"
        "tailscale up"
      ];

      env = [
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
        "TERMINAL,kitty"
      ];

      input = {
        kb_layout = "us";
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
        drop_shadow        = true;
        shadow_range       = 4;
        shadow_render_power = 3;
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

        # Screenshots
        ", PRINT,       exec, grimblast copy area"
        "$mod, PRINT,   exec, grimblast copy output"
        "$mod SHIFT, PRINT, exec, grimblast save area ~/Pictures/$(date +%Y-%m-%d_%H-%M-%S).png"

        # Clipboard history
        "$mod, X, exec, cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"

        # Emoji picker
        "$mod, period, exec, wofi-emoji"

        # Focus
        "$mod, left,  movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up,    movefocus, u"
        "$mod, down,  movefocus, d"

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

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
    };
  };

  # ─── Dunst ────────────────────────────────────────────────────────────────────
  services.dunst = {
    enable = true;
    settings = {
      global = {
        width       = 300;
        height      = 300;
        offset      = "30x50";
        origin      = "top-right";
        transparency = 10;
        frame_color = "#33ccff";
        font        = "JetBrains Mono 10";
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
