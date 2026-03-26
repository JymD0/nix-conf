{ config, pkgs, lib, user, zen-browser, ... }:

let
  eppOnBattery = pkgs.writeShellScript "epp-on-battery" ''
    for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
      echo power > "$f"
    done
  '';
  eppOnAC = pkgs.writeShellScript "epp-on-ac" ''
    for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
      echo balanced_performance > "$f"
    done
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
    "amdgpu.abmlevel=0"      # Better color accuracy
    "amd_pstate=active"      # AMD P-State EPP — more efficient CPU power management
    "mem_sleep_default=deep" # S3 deep sleep — much lower suspend power draw
    # Hibernate resume — offset found via: filefrag -v /swapfile | awk 'NR==4{print $4}' | tr -d '.'
    "resume_offset=5408768"
  ];

  boot.resumeDevice = "/dev/nvme0n1p5";

  # Prevent wake in backpack
  services.udev.extraRules = lib.mkAfter ''
    SUBSYSTEM=="usb", DRIVERS=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0012", ATTR{power/wakeup}="disabled"
    SUBSYSTEM=="usb", DRIVERS=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0014", ATTR{power/wakeup}="disabled"

    # EPP: prefer efficiency on battery, balanced-performance on AC
    SUBSYSTEM=="power_supply", ATTR{online}=="0", RUN+="${eppOnBattery}"
    SUBSYSTEM=="power_supply", ATTR{online}=="1", RUN+="${eppOnAC}"

  '';

  # Hostname
  networking.hostName = user.hostname;
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = false; # disabled — causes reconnect failures after suspend on MT7922

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

  # Keyboard layout (system-wide, German)
  services.xserver.xkb = {
    layout = user.keyboardLayout;
    variant = "";
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

  # Reduce microphone gain to prevent clipping/noise on Framework 16
  # ALC295 internal mic defaults to max boost (+30dB) and max capture (+29.5dB),
  # which causes constant static and clipping. Lower both at the ALSA level.
  services.pipewire.wireplumber.extraConfig."99-mic-gain" = {
    "monitor.alsa.rules" = [
      {
        matches = [{ "node.name" = "~alsa_input.*"; }];
        actions.update-props = {
          "node.volume" = 0.4;
        };
      }
    ];
  };

  # Fix ALSA-level mic gain: reduce Mic Boost from +30dB to +10dB
  # and Capture Volume from max (63) to 25 to eliminate static/clipping
  systemd.services.fix-mic-gain = {
    description = "Set sane ALSA mic gain for ALC295";
    after = [ "sound.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = let
        amixer = "${pkgs.alsa-utils}/bin/amixer";
      in pkgs.writeShellScript "fix-mic-gain" ''
        # Mic Boost: 1 out of 3 = +10dB (default 3 = +30dB)
        ${amixer} -c 1 sset 'Mic Boost' 1
        # Capture Volume: 25 out of 63 (~-11dB, default 63 = +29.5dB)
        ${amixer} -c 1 sset 'Capture' 25
      '';
    };
  };

  # Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Fingerprint reader
  services.fprintd.enable = true;

  # PAM for hyprlock — fingerprint is handled natively by hyprlock via D-Bus,
  # so disable fprintAuth in PAM to avoid blocking the password path.
  security.pam.services.hyprlock = {
    fprintAuth = false;
  };

  # i2c access for ddcutil (external monitor brightness via DDC/CI)
  hardware.i2c.enable = true;

  # Power management (critical for laptop battery life)
  services.power-profiles-daemon.enable = true;
  powerManagement.powertop.enable = false; # disabled — conflicts with power-profiles-daemon and causes USB HID autosuspend lag

  # Swapfile required for hibernate — must be >= RAM size (32 GB)
  swapDevices = [{
    device = "/swapfile";
    size = 32768; # MB
  }];

  # Hibernate after 30min of suspend (requires swap >= RAM size)
  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "30m";
  };

  # Lid switch: suspend-then-hibernate on battery, lock when plugged in
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "lock";
  };

  # Fix WiFi and touchpad not working after suspend/resume
  # Framework 16 AMD: mt7921e (WiFi) and i2c_hid_acpi (touchpad) need
  # to be reloaded after S3 resume to reinitialize properly.
  systemd.services.post-resume-fix = {
    description = "Reload WiFi and touchpad drivers after resume";
    after = [ "suspend.target" "hibernate.target" "suspend-then-hibernate.target" ];
    wantedBy = [ "suspend.target" "hibernate.target" "suspend-then-hibernate.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "post-resume-fix" ''
        # Reload WiFi driver (MediaTek MT7922 / mt7921e)
        ${pkgs.kmod}/bin/modprobe -r mt7921e && ${pkgs.kmod}/bin/modprobe mt7921e
        # Reload touchpad driver (I2C HID)
        ${pkgs.kmod}/bin/modprobe -r i2c_hid_acpi && ${pkgs.kmod}/bin/modprobe i2c_hid_acpi
      '';
    };
  };
  # Firmware updates (Framework ships updates via fwupd)
  services.fwupd.enable = true;

  # Hyprland
  programs.hyprland = {
    enable = true;
    withUWSM = true; # recommended since NixOS 24.11
    xwayland.enable = true;
  };

  # Set keyboard layout for Hyprland (Wayland)
  environment.sessionVariables.XKB_DEFAULT_LAYOUT = user.keyboardLayout;

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
  security.pam.services.greetd.enableGnomeKeyring = true; # unlock keyring on login

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

  users.users.${user.username} = {
    isNormalUser = true;
    description = user.fullName;
    shell = pkgs.zsh;
    extraGroups = [ "networkmanager" "wheel" "video" "audio" "i2c" "docker" "dialout" ];
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
