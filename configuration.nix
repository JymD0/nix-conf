{ config, pkgs, lib, zen-browser, ... }:

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

  # Power management (critical for laptop battery life)
  services.power-profiles-daemon.enable = true;
  services.thermald.enable = true;

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

  # regreet — GTK4 graphical greeter running inside a minimal Hyprland compositor
  # This gives a proper Wayland login screen that matches the desktop aesthetic.
  programs.regreet = {
    enable = true;
    # GTK settings for the greeter (Dracula dark theme)
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
      background = {
        # Set to your preferred wallpaper path, e.g. a file copied into /etc/nixos
        # path = "/etc/nixos/wallpaper.jpg";
        fit = "Cover";
      };
      GTK = {
        application_prefer_dark_theme = true;
      };
    };
  };

  # greetd launches a minimal Hyprland session which regreet renders inside
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.hyprland}/bin/Hyprland";
      user = "greeter";
    };
  };

  # Firewall
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
  };

  # Tailscale
  services.tailscale.enable = true;

  # SSH agent
  programs.ssh.startAgent = true;

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
    brightnessctl   # backlight control
  ];

  # User account
  users.users.yourUsername = {
    isNormalUser = true;
    description = "Your Name";
    extraGroups = [ "networkmanager" "wheel" "video" "audio" ];
  };

  # XDG portals — required for screensharing and file pickers under Hyprland
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
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
