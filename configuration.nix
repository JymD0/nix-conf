{ config, lib, pkgs, user, zen-browser, ... }:

let
  grubTheme =
    let
      base = pkgs.fetchFromGitHub {
        owner = "dracula";
        repo = "grub";
        rev = "0e721d99dbf0d5d6c4fd489b88248365b7a60d12";
        hash = "sha256-SBAXGJbNYdr89FSlqzgkiW/c23yTHYvNxxU8F1hMfXI=";
      } + "/dracula";
    in
    pkgs.runCommand "grub-theme-patched" { } ''
      cp -r ${base} $out
      chmod -R u+w $out
      cp ${./assets/grub-logo.png} $out/logo.png
      sed -i '/desktop-image-scale-method/d' $out/theme.txt
      substituteInPlace $out/theme.txt \
        --replace-fail "left = 50%-50" "left = 50%-480" \
        --replace-fail "top = 50%-50" "top = 25%"
    '';

in

{
  imports = [
    ./hardware-configuration.nix
  ] ++ lib.optionals (user.hardware == "framework") [
    ./modules/hardware/fw16.nix
  ];

  # Allow unfree packages (VS Code, Discord, etc.)
  nixpkgs.config.allowUnfree = true;

  # Bootloader
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    configurationLimit = 1;
    theme = grubTheme;
    splashImage = null;
    extraEntries = lib.optionalString (user.windowsEfiUuid != "") ''
      menuentry "Windows" {
        insmod part_gpt
        insmod fat
        insmod chain
        search --no-floppy --fs-uuid --set=root ${user.windowsEfiUuid}
        chainloader /EFI/Microsoft/Boot/bootmgfw.efi
      }
    '';
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelParams = [ "logo.nologo" ];

  # Hostname
  networking.hostName = user.hostname;
  networking.networkmanager.enable = true;

  # Time zone & locale (English language, Austrian region)
  time.timeZone = user.timezone;
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = user.locale;
    LC_IDENTIFICATION = user.locale;
    LC_MEASUREMENT = user.locale;
    LC_MONETARY = user.locale;
    LC_NAME = user.locale;
    LC_NUMERIC = user.locale;
    LC_PAPER = user.locale;
    LC_TELEPHONE = user.locale;
    LC_TIME = user.locale;
  };

  # Keyboard layouts (system-wide: German + Colemak-DH ISO)
  services.xserver.xkb = {
    layout = "${user.keyboardLayout},us";
    variant = ",colemak_dh_iso";
  };
  console.keyMap = user.keyboardLayout;

  # Audio
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true; # needed by OBS audio
  };

  # Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # i2c access for ddcutil (external monitor brightness via DDC/CI)
  hardware.i2c.enable = true;

  # Sunshine — remote desktop streaming (use Moonlight client on Windows)
  services.sunshine = {
    enable = true;
    autoStart = true;
    openFirewall = true;
    capSysAdmin = true; # needed for KMS capture
    settings = {
      fec_percentage = 0; # disabled, no packet loss on gigabit LAN
      encoder = "vaapi"; # pin hardware encoder, skip nvenc probe
    };
  };

  # uinput device needed for Sunshine's virtual keyboard/mouse/gamepad input
  hardware.uinput.enable = true;

  # Steam
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  # Hyprland
  programs.hyprland = {
    enable = true;
    withUWSM = true; # recommended since NixOS 24.11
    xwayland.enable = true;
  };

  # Set keyboard layout for Hyprland (Wayland)
  environment.sessionVariables.XKB_DEFAULT_LAYOUT = "${user.keyboardLayout},us";
  environment.sessionVariables.XKB_DEFAULT_VARIANT = ",colemak_dh_iso";

  # Auto-login via greetd — hyprlock handles authentication on startup
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "start-hyprland";
      user = user.username;
    };
  };

  # Firewall
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" "docker0" ];
    allowedTCPPortRanges = [ { from = 1714; to = 1764; } ];  # Valent (KDE Connect)
    allowedUDPPortRanges = [ { from = 1714; to = 1764; } ];  # Valent (KDE Connect)
    allowedTCPPorts = [ 49152 ];                              # rquickshare (Quick Share)
    allowedUDPPorts = [ config.services.tailscale.port ];
  };

  # Tailscale
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  # Docker
  virtualisation.docker.enable = true;
  virtualisation.docker.daemon.settings = {
    dns = [ "8.8.8.8" "8.8.4.4" ];
  };

  # Route Docker bridge traffic via main table, bypassing Tailscale exit node
  networking.localCommands = ''
    ip rule add from 172.17.0.0/16 lookup main priority 100 2>/dev/null || true
  '';

  # SSH — GNOME Keyring acts as the SSH agent (auto-unlocks keys at login)
  programs.ssh.startAgent = false; # disabled — gnome-keyring-daemon provides the agent
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = false; # auto-login skips PAM password, so this just creates an empty locked login keyring
  # hyprlock handles fingerprint auth itself via D-Bus, so disable pam_fprintd
  # in its PAM stack to avoid blocking password auth while fprintd waits for a scan
  security.pam.services.hyprlock = {
    fprintAuth = false;
  };

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # System packages
  environment.systemPackages = with pkgs; [
    git
    wget
    curl
    vim
    gnumake
    python3
    wl-clipboard
    zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default

    # Hyprland extras
    brightnessctl   # internal backlight control
    ddcutil         # external monitor brightness via DDC/CI
  ];

  # User account
  programs.zsh.enable = true;
  programs.ydotool.enable = true; # uinput daemon for mouse click/scroll automation

  users.users.${user.username} = {
    isNormalUser = true;
    description = user.fullName;
    shell = pkgs.zsh;
    extraGroups = [ "networkmanager" "wheel" "video" "audio" "i2c" "docker" "dialout" "input" "ydotool" ];
  };

  # XDG portals — required for screensharing and file pickers under Hyprland
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland # Wayland screen capture (OBS, screenshare)
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  # Virtual camera support for OBS
  boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
  boot.kernelModules = [ "v4l2loopback" ];
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=10 card_label="OBS Virtual Camera" exclusive_caps=1
    options snd_hda_intel power_save=1
  '';

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
