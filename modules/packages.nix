{ config, pkgs, lib, user, ... }:

{
  # ─── Fonts ─────────────────────────────────────────────────────────────────────
  fonts.fontconfig.enable = true;

  # ─── Packages ───────────────────────────────────────────────────────────────────
  home.packages = with pkgs; [
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
    sound-theme-freedesktop  # standard notification sounds
    libcanberra-gtk3         # canberra-gtk-play for playing event sounds

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

    # Time tracking
    aw-server-rust
    awatcher

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
    vlc
    thunderbird

    # Fonts
    noto-fonts-color-emoji
    jetbrains-mono
    font-awesome
    nerd-fonts.jetbrains-mono

    # Icons
    papirus-icon-theme

    # SSH & File Transfer
    termscp
    seahorse  # GUI for managing GNOME Keyring (SSH keys, passwords, certificates)
    libsecret # CLI (secret-tool) for keyring access — used by ai script

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

    # Language toolchains
    nodejs
    nodePackages.typescript
    gcc
    jdk
    kotlin
    go
    rustc
    cargo

    # Linters & formatters
    shellcheck
    ruff
    nixfmt-rfc-style
    statix
    deadnix
    cppcheck
    ktlint
    google-java-format
    yamllint
    taplo
    html-tidy
    nodePackages.prettier
    nodePackages.stylelint
    markdownlint-cli2

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
  ];

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
        "terminal.integrated.defaultProfile.linux" = "zsh";
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

  # ─── XDG dirs ──────────────────────────────────────────────────────────────────
  xdg = {
    enable = true;
    userDirs = {
      enable = true;
      createDirectories = true;
      setSessionVariables = true;
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
      "khal/config".text = let
        extraCalSections = lib.concatStrings (lib.mapAttrsToList (name: cal: ''

          [[${builtins.replaceStrings ["-"] ["_"] name}]]
          path = ~/.local/share/vdirsyncer/${name}/
          type = calendar
          color = ${cal.color}
        '') user.extraCalendars);
      in ''
        [calendars]

        [[personal]]
        path = ~/.local/share/vdirsyncer/calendar/*
        type = discover
        color = light magenta
        ${extraCalSections}
        [locale]
        timeformat = %H:%M
        dateformat = %d.%m.%Y
        longdateformat = %d.%m.%Y
        datetimeformat = %d.%m.%Y %H:%M
        longdatetimeformat = %d.%m.%Y %H:%M
        default_timezone = ${user.timezone}
        firstweekday = 0

        [default]
        default_calendar = ${user.defaultCalendar}
      '';

      # ─── vdirsyncer config ────────────────────────────────────────────────────
      "vdirsyncer/config".text = let
        extraCalPairs = lib.concatStrings (lib.mapAttrsToList (name: cal: let
          safeName = builtins.replaceStrings ["-"] ["_"] name;
        in ''

          [pair ${safeName}]
          a = "${safeName}_local"
          b = "${safeName}_remote"
          collections = null

          [storage ${safeName}_local]
          type = "filesystem"
          path = "~/.local/share/vdirsyncer/${name}/"
          fileext = ".ics"

          [storage ${safeName}_remote]
          type = "http"
          url.fetch = ["command", "${pkgs.libsecret}/bin/secret-tool", "lookup", "service", "vdirsyncer-ical", "attribute", "${cal.keyringAttr}"]
        '') user.extraCalendars);
      in ''
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
        client_id.fetch = ["command", "${pkgs.libsecret}/bin/secret-tool", "lookup", "service", "vdirsyncer", "attribute", "client_id"]
        client_secret.fetch = ["command", "${pkgs.libsecret}/bin/secret-tool", "lookup", "service", "vdirsyncer", "attribute", "client_secret"]
        ${extraCalPairs}
      '';
    };
  };
}
