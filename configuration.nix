{ config, pkgs, lib, zen-browser, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Allow unfree packages (VS Code, Discord, etc.)
  nixpkgs.config.allowUnfree = true;

  # Bootloader
  boot.loader.systemd-boot.enable = true;
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

  # Time zone & locale
  time.timeZone = "Europe/Vienna";
  i18n.defaultLocale = "en_US.UTF-8";

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

  # Fingerprint reader
  services.fprintd.enable = true;

  # Hyprland
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # Enable greetd with tuigreet for Hyprland login
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        # tuigreet was moved out of greetd attrset in recent nixpkgs
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd Hyprland";
        user = "greeter";
      };
    };
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
  ];

  # User account
  users.users.yourUsername = {
    isNormalUser = true;
    description = "Your Name";
    extraGroups = [ "networkmanager" "wheel" "video" "audio" ];
  };

  system.stateVersion = "24.11";
}
