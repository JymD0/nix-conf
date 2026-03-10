{ config, pkgs, lib, zen-browser, ... }:

let
  # Startup script for the greeter Hyprland session:
  # wait for regreet to exit (login done), then exit Hyprland so greetd
  # can launch the user's session.
  regreetStartup = pkgs.writeShellScript "regreet-startup" ''
    ${pkgs.greetd.regreet}/bin/regreet
    ${pkgs.hyprland}/bin/hyprctl dispatch exit 0
  '';

  # Minimal Hyprland config used only for the login screen.
  # - No animations / no splash
  # - windowrulev2 makes regreet fullscreen on whichever monitor it opens on
  #   (fixes the "split across two monitors" bug that cage produces)
  regreetHyprConf = pkgs.writeText "greetd-hyprland.conf" ''
    monitor = , preferred, auto, 1

    exec-once = ${regreetStartup}

    windowrulev2 = fullscreen, class:re.greyber.regreet

    general {
      gaps_in  = 0
      gaps_out = 0
      col.active_border  = rgba(bd93f9ff)
      col.inactive_border = rgba(44475aff)
    }

    decoration {
      rounding = 0
      blur {
        enabled   = true
        size      = 8
        passes    = 3
      }
      drop_shadow = false
    }

    animations {
      enabled = false
    }

    misc {
      disable_hyprland_logo    = true
      disable_splash_rendering = true
      force_default_wallpaper  = 0
    }

    input {
      kb_layout = de
    }
  '';

  # Dracula-themed GTK4 CSS, symlinked into the greeter user's config dir
  # via systemd-tmpfiles so it is picked up by every regreet launch.
  regreetCss = pkgs.writeText "regreet-dracula.css" ''
    /* ── Dracula palette ─────────────────────────────────────── */
    /* bg=#282a36  darker=#1e1f29  surface=#44475a               */
    /* comment=#6272a4  fg=#f8f8f2  subtle=#a8a8b3               */
    /* purple=#bd93f9  pink=#ff79c6  cyan=#8be9fd  green=#50fa7b */

    /* ── Full-screen background ─────────────────────────────── */
    window, .background {
      background:
        radial-gradient(ellipse at 20% 80%, rgba(189,147,249,0.08) 0%, transparent 50%),
        radial-gradient(ellipse at 80% 20%, rgba(139,233,253,0.06) 0%, transparent 50%),
        linear-gradient(160deg, #1e1f29 0%, #282a36 40%, #1e1f29 100%);
      color: #f8f8f2;
    }

    /* ── Login card — frosted glass ─────────────────────────── */
    frame, .card, box.login {
      background-color: rgba(68, 71, 90, 0.55);
      border-radius: 20px;
      border: 1px solid rgba(98, 114, 164, 0.4);
      box-shadow:
        0 8px 32px rgba(0, 0, 0, 0.5),
        0 0 0 1px rgba(248, 248, 242, 0.03),
        inset 0 1px 0 rgba(248, 248, 242, 0.06);
      padding: 24px;
      margin: 8px;
    }

    /* ── Typography ─────────────────────────────────────────── */
    label {
      color: #f8f8f2;
    }
    label.dim-label {
      color: #6272a4;
    }

    /* ── Text inputs ────────────────────────────────────────── */
    entry {
      background-color: rgba(30, 31, 41, 0.7);
      color: #f8f8f2;
      border: 1px solid rgba(98, 114, 164, 0.5);
      border-radius: 10px;
      caret-color: #bd93f9;
      padding: 8px 14px;
      min-height: 20px;
      transition: all 200ms ease;
    }
    entry:focus {
      border-color: #bd93f9;
      box-shadow:
        0 0 0 2px rgba(189, 147, 249, 0.25),
        inset 0 0 0 1px rgba(189, 147, 249, 0.15);
      background-color: rgba(30, 31, 41, 0.9);
    }
    entry placeholder {
      color: rgba(98, 114, 164, 0.7);
    }

    /* ── Generic buttons ────────────────────────────────────── */
    button {
      background-color: transparent;
      color: #f8f8f2;
      border-radius: 10px;
      padding: 6px 16px;
      min-height: 20px;
      transition: all 150ms ease;
    }
    button:hover {
      background-color: rgba(98, 114, 164, 0.2);
    }
    button:active {
      background-color: rgba(98, 114, 164, 0.35);
    }

    /* ── Primary / login button ─────────────────────────────── */
    button.suggested-action {
      background: linear-gradient(135deg, #bd93f9 0%, #a87bf5 100%);
      color: #1e1f29;
      font-weight: bold;
      border: none;
      box-shadow:
        0 4px 16px rgba(189, 147, 249, 0.3),
        0 1px 3px rgba(0, 0, 0, 0.2);
      padding: 8px 28px;
    }
    button.suggested-action:hover {
      background: linear-gradient(135deg, #cfa9fb 0%, #bd93f9 100%);
      box-shadow:
        0 6px 24px rgba(189, 147, 249, 0.4),
        0 2px 6px rgba(0, 0, 0, 0.3);
    }
    button.suggested-action:active {
      background: linear-gradient(135deg, #a87bf5 0%, #9b6de8 100%);
      box-shadow: 0 2px 8px rgba(189, 147, 249, 0.2);
    }

    /* ── Session / user dropdowns ───────────────────────────── */
    combobox button, .combo button {
      background-color: rgba(68, 71, 90, 0.6);
      color: #f8f8f2;
      border: 1px solid rgba(98, 114, 164, 0.4);
      border-radius: 10px;
      padding: 6px 12px;
      min-height: 20px;
    }
    combobox button:hover, .combo button:hover {
      background-color: rgba(68, 71, 90, 0.85);
      border-color: #bd93f9;
    }

    /* ── Dropdown popover ───────────────────────────────────── */
    popover, .popover {
      background-color: rgba(40, 42, 54, 0.95);
      border: 1px solid rgba(98, 114, 164, 0.4);
      border-radius: 12px;
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.5);
      padding: 4px;
    }
    popover modelbutton, .popover modelbutton {
      border-radius: 8px;
      padding: 6px 12px;
      transition: background-color 150ms ease;
    }
    row:selected, row:hover,
    popover modelbutton:hover, .popover modelbutton:hover {
      background-color: rgba(189, 147, 249, 0.2);
    }
    row:selected {
      background-color: rgba(189, 147, 249, 0.3);
    }

    /* ── Scrollbar — keep thin and subtle ───────────────────── */
    scrollbar slider {
      background-color: rgba(98, 114, 164, 0.3);
      border-radius: 99px;
      min-width: 4px;
    }
    scrollbar slider:hover {
      background-color: rgba(189, 147, 249, 0.5);
    }

    /* ── Power / action buttons row ─────────────────────────── */
    button.destructive-action {
      color: #ff5555;
    }
    button.destructive-action:hover {
      background-color: rgba(255, 85, 85, 0.15);
    }
  '';
in

{
  imports = [ ./hardware-configuration.nix ];

  # Allow unfree packages (VS Code, Discord, etc.)
  nixpkgs.config.allowUnfree = true;

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.efi.canTouchEfiVariables = true;

  # Latest kernel for best FW16 support
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Framework-specific tweaks
  boot.kernelParams = [
    "amdgpu.abmlevel=0" # Better color accuracy
  ];

  # Prevent wake in backpack
  services.udev.extraRules = lib.mkAfter ''
    SUBSYSTEM=="usb", DRIVERS=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0012", ATTR{power/wakeup}="disabled"
    SUBSYSTEM=="usb", DRIVERS=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0014", ATTR{power/wakeup}="disabled"
  '';

  # Hostname
  networking.hostName = "yourHostname";
  networking.networkmanager.enable = true;

  # Time zone & locale (English language, Austrian region)
  time.timeZone = "Europe/Vienna";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_AT.UTF-8";
    LC_IDENTIFICATION = "de_AT.UTF-8";
    LC_MEASUREMENT = "de_AT.UTF-8";
    LC_MONETARY = "de_AT.UTF-8";
    LC_NAME = "de_AT.UTF-8";
    LC_NUMERIC = "de_AT.UTF-8";
    LC_PAPER = "de_AT.UTF-8";
    LC_TELEPHONE = "de_AT.UTF-8";
    LC_TIME = "de_AT.UTF-8";
  };

  # Keyboard layout (system-wide, German)
  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };
  console.keyMap = "de";

  # Audio
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Fingerprint reader already enabled via nixos-hardware framework module
  # (services.fprintd.enable = lib.mkDefault true in framework/16-inch/common)

  # PAM fingerprint auth for hyprlock and greetd
  security.pam.services.hyprlock = {
    fprintAuth = true;
  };
  security.pam.services.greetd.fprintAuth = true;

  # i2c access for ddcutil (external monitor brightness via DDC/CI)
  hardware.i2c.enable = true;

  # Power management (critical for laptop battery life)
  services.power-profiles-daemon.enable = true;
  # Firmware updates (Framework ships updates via fwupd)
  services.fwupd.enable = true;

  # Hyprland
  programs.hyprland = {
    enable = true;
    withUWSM = true; # recommended since NixOS 24.11
    xwayland.enable = true;
  };

  # Set keyboard layout for Hyprland (Wayland)
  environment.sessionVariables.XKB_DEFAULT_LAYOUT = "de";

  # regreet — GTK4 graphical greeter, running inside a dedicated Hyprland
  # compositor session instead of cage.  Hyprland correctly handles multiple
  # monitors (cage splits the window across displays) and gives us full
  # window-rule support for reliable fullscreen behaviour.
  programs.regreet = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    font = {
      name = "JetBrains Mono";
      size = 14;
      package = pkgs.jetbrains-mono;
    };
    settings = {
      background.fit = "Cover";
      GTK.application_prefer_dark_theme = true;
    };
  };

  # Replace the cage-based greetd command with our Hyprland session.
  services.greetd.settings.default_session.command =
    lib.mkForce "${pkgs.hyprland}/bin/Hyprland --config ${regreetHyprConf}";

  # Symlink Dracula CSS into the greeter user's GTK4 config dir so regreet
  # picks it up without any runtime path argument.
  systemd.tmpfiles.rules = [
    "d  /var/lib/greetd/.config                  0755 greeter greeter -"
    "d  /var/lib/greetd/.config/gtk-4.0          0755 greeter greeter -"
    "L+ /var/lib/greetd/.config/gtk-4.0/gtk.css  -    greeter greeter - ${regreetCss}"
  ];

  # Firewall
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
  };

  # Tailscale
  services.tailscale.enable = true;

  # Docker
  virtualisation.docker.enable = true;

  # SSH agent
  programs.ssh.startAgent = true;
  programs.ssh.extraConfig = lib.mkForce "";

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # System packages
  environment.systemPackages = with pkgs; [
    git
    wget
    curl
    vim
    wl-clipboard
    zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default

    # Hyprland extras
    brightnessctl   # internal backlight control
    ddcutil         # external monitor brightness via DDC/CI
  ];

  # User account
  users.users.yourUsername = {
    isNormalUser = true;
    description = "Your Name";
    extraGroups = [ "networkmanager" "wheel" "video" "audio" "i2c" "docker" ];
  };

  # XDG portals — required for screensharing and file pickers under Hyprland
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  # Electron apps (VS Code, Discord, etc.) render natively on Wayland
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # Nix store maintenance
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true;

  system.stateVersion = "24.11";
}
