{ config, pkgs, lib, user, ... }:

let
  ledmatrix-pkg = pkgs.python3.pkgs.buildPythonApplication {
    pname = "ledmatrix";
    version = "0.1.0";
    src = ../scripts/ledmatrix;
    format = "pyproject";
    nativeBuildInputs = [ pkgs.python3.pkgs.setuptools ];
    doCheck = false;
  };

  # Wraps hyprlock so the LED matrix shows a lock/unlock animation on every lock.
  hyprlock-led = pkgs.writeShellScriptBin "hyprlock-led" ''
    set -euo pipefail
    trap '${ledmatrix-pkg}/bin/ledmatrix-unlock unlock &' EXIT
    ${ledmatrix-pkg}/bin/ledmatrix-unlock lock &
    ${pkgs.hyprlock}/bin/hyprlock "$@"
  '';

  # Screen off, lights off, but wifi and processes keep running.
  # Does NOT lock the session immediately (that would kill remote-control
  # and other Wayland clients). Instead it blanks everything and polls for
  # user input (DPMS wake). When the user wakes the screen, hyprlock kicks
  # in so they still need to authenticate.
  work-mode = pkgs.writeShellScriptBin "work-mode" ''
    set -euo pipefail
    HC="${pkgs.hyprland}/bin/hyprctl"
    IC="${pkgs.inputmodule-control}/bin/inputmodule-control"
    BC="${pkgs.brightnessctl}/bin/brightnessctl"
    DEV="/dev/ttyACM0"
    INHIBIT_PID=""
    SUPPRESS_DIR="''${XDG_RUNTIME_DIR:-/tmp}/hypridle-suppress"
    SUPPRESS_FLAG="$SUPPRESS_DIR/work-mode"
    mkdir -p "$SUPPRESS_DIR"

    # suppress hypridle via shared flag
    touch "$SUPPRESS_FLAG"
    systemctl --user stop hypridle.service 2>/dev/null || true

    # save current keyboard backlight so we can restore it
    KBD_BRIGHTNESS=$("$BC" -d framework_laptop::kbd_backlight g 2>/dev/null || echo "")

    cleanup() {
      [ -n "$INHIBIT_PID" ] && kill "$INHIBIT_PID" 2>/dev/null && wait "$INHIBIT_PID" 2>/dev/null || true

      "$HC" keyword misc:mouse_move_enables_dpms false
      "$HC" keyword misc:key_press_enables_dpms false
      "$HC" dispatch dpms on

      # release suppress flag, only restart hypridle if no other suppressor is active
      rm -f "$SUPPRESS_FLAG"
      if [ -z "$(ls -A "$SUPPRESS_DIR" 2>/dev/null)" ]; then
        systemctl --user start hypridle.service 2>/dev/null || true
      fi

      # restore keyboard backlight
      [ -n "$KBD_BRIGHTNESS" ] && "$BC" -d framework_laptop::kbd_backlight s "$KBD_BRIGHTNESS" 2>/dev/null || true

      # wake the LED matrix
      [ -e "$DEV" ] && "$IC" --serial-dev "$DEV" led-matrix --sleeping false 2>/dev/null || true
    }
    trap cleanup EXIT

    # hold a sleep inhibitor in the background for the lifetime of this script
    ${pkgs.systemd}/bin/systemd-inhibit \
      --what=sleep:idle --who=work-mode --why="Work mode active" \
      --mode=block sleep infinity &
    INHIBIT_PID=$!

    # let input wake DPMS (hyprland defaults these to false)
    "$HC" keyword misc:mouse_move_enables_dpms true
    "$HC" keyword misc:key_press_enables_dpms true

    # turn off keyboard backlight
    "$BC" -d framework_laptop::kbd_backlight s 0 2>/dev/null || true

    # put the LED matrix to sleep
    [ -e "$DEV" ] && "$IC" --serial-dev "$DEV" led-matrix --sleeping true 2>/dev/null || true

    # turn screen off (no session lock, so Claude and remote-control keep working)
    "$HC" dispatch dpms off

    # poll until the user wakes the screen (any input turns DPMS back on)
    while true; do
      sleep 1
      if "$HC" monitors -j 2>/dev/null | grep -q '"dpmsStatus": true'; then
        break
      fi
    done

    # screen is back on, lock it now
    hyprlock-led
  '';
in

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
    wtype

    # Tools (used by walker menus and keybindings)
    hyprpicker     # color picker (Wayland)
    pass           # password manager
    wl-clipboard   # wl-copy / wl-paste

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
    nwg-displays

    # Lock screen (hyprlock-led wraps hyprlock with LED matrix animations)
    hyprlock
    hyprlock-led
    work-mode

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
    prismlauncher  # Minecraft launcher
    foxglove-studio
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

    # Git
    gh
    tea  # forgejo/gitea CLI

    # SSH & File Transfer
    termscp
    seahorse  # GUI for managing GNOME Keyring (SSH keys, passwords, certificates)
    libsecret # CLI (secret-tool) for keyring access — used by ai script

    # Wallpaper
    awww
    variety

    # Calendar
    khal
    vdirsyncer

    # Document / publishing
    texliveMedium
    pandoc    # convert markdown to PDF (uses LaTeX backend)
    typst     # modern typesetting system

    # Utilities
    ripgrep
    fd
    jq
    unzip
    p7zip
    unrar
    zstd

    # Language toolchains
    nodejs
    typescript
    gcc
    jdk
    kotlin
    go
    rustc
    cargo

    # Linters & formatters
    shellcheck
    ruff
    nixfmt
    statix
    deadnix
    cppcheck
    ktlint
    google-java-format
    yamllint
    taplo
    html-tidy
    prettier
    stylelint
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

    # LED matrix animations
    ledmatrix-pkg
    socat

    # Misc
    xdg-utils

    # Camera (webcam viewer / v4l2 tools for OBS)
    v4l-utils

    # Music
    spotify

    # Phone integration
    valent        # KDE Connect protocol (notifications, clipboard, media)
    rquickshare   # Google Quick Share for Linux (native file transfer)
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

  xdg.configFile."obs-studio/basic/profiles/Untitled/basic.ini" = {
    force = true;
    text = ''
    [General]
    Name=Untitled

    [SimpleOutput]
    FilePath=/home/jymdo/Videos

    [AdvOut]
    RecFilePath=/home/jymdo/Videos
  '';
  };

  # ─── XDG dirs ──────────────────────────────────────────────────────────────────
  xdg = {
    enable = true;

    # Keep Chromium available for Playwright without letting it become the default browser.
    mimeApps = {
      enable = true;
      defaultApplications = {
        "application/pdf" = "zen.desktop";
        "application/x-extension-htm" = "zen.desktop";
        "application/x-extension-html" = "zen.desktop";
        "application/x-extension-shtml" = "zen.desktop";
        "application/x-extension-xht" = "zen.desktop";
        "application/x-extension-xhtml" = "zen.desktop";
        "application/xhtml+xml" = "zen.desktop";
        "text/html" = "zen.desktop";
        "x-scheme-handler/chrome" = "zen.desktop";
        "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
        "x-scheme-handler/http" = "zen.desktop";
        "x-scheme-handler/https" = "zen.desktop";
      };
    };

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
      "mimeapps.list".force = true;

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

  # rquickshare settings: static port for firewall + download path
  xdg.dataFile."dev.mandre.rquickshare/.settings.json" = {
    force = true;
    text = builtins.toJSON {
    visibility = "Everyone";
    download_path = "${config.home.homeDirectory}/Downloads/QuickShare";
    port = 49152;
    realclose = false;
    };
  };
}
