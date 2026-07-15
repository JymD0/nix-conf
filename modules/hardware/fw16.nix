{ config, pkgs, lib, ... }:

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
  # GPU (AMD Phoenix iGPU)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Latest kernel for best FW16 support
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Framework-specific kernel tweaks
  boot.kernelParams = [
    "amdgpu.abmlevel=0"      # Better color accuracy
    "amd_pstate=active"      # AMD P-State EPP, more efficient CPU power management
    "mem_sleep_default=deep" # S3 deep sleep, much lower suspend power draw
    # Hibernate resume offset, found via: filefrag -v /swapfile | awk 'NR==4{print $4}' | tr -d '.'
    "resume_offset=5408768"
  ];

  # Machine-specific hibernate resume device
  boot.resumeDevice = "/dev/nvme1n1p5";

  # Prevent wake in backpack (Framework USB VID 32ac) + EPP power tuning
  services.udev.extraRules = lib.mkAfter ''
    SUBSYSTEM=="usb", DRIVERS=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0012", ATTR{power/wakeup}="disabled"
    SUBSYSTEM=="usb", DRIVERS=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0014", ATTR{power/wakeup}="disabled"

    SUBSYSTEM=="power_supply", ATTR{online}=="0", RUN+="${eppOnBattery}"
    SUBSYSTEM=="power_supply", ATTR{online}=="1", RUN+="${eppOnAC}"
  '';

  # MT7922 WiFi: powersave causes reconnect failures after suspend
  networking.networkmanager.wifi.powersave = false;

  # Fingerprint reader
  services.fprintd.enable = true;

  # LED matrix input module
  services.udev.packages = [ pkgs.inputmodule-control ];
  environment.systemPackages = [ pkgs.inputmodule-control ];

  # UPower — required by ac-monitor for plug/unplug events
  services.upower.enable = true;

  # Framework ships firmware updates via fwupd
  services.fwupd.enable = true;

  # Fan control (Framework EC-aware curves)
  hardware.fw-fanctrl.enable = true;
  hardware.fw-fanctrl.config = {
    defaultStrategy = "default";
    strategies = {
      default = {
        fanSpeedUpdateFrequency = 5;
        movingAverageInterval = 30;
        speedCurve = [
          { temp = 0;  speed = 0; }
          { temp = 50; speed = 15; }
          { temp = 65; speed = 25; }
          { temp = 70; speed = 35; }
          { temp = 75; speed = 50; }
          { temp = 80; speed = 80; }
          { temp = 85; speed = 100; }
        ];
      };
      cool = {
        fanSpeedUpdateFrequency = 5;
        movingAverageInterval = 10;
        speedCurve = [
          { temp = 0;  speed = 25; }
          { temp = 45; speed = 35; }
          { temp = 55; speed = 50; }
          { temp = 65; speed = 65; }
          { temp = 70; speed = 80; }
          { temp = 75; speed = 100; }
        ];
      };
    };
  };

  # Power management (critical for laptop battery life)
  services.power-profiles-daemon.enable = true;
  powerManagement.powertop.enable = false; # disabled: conflicts with power-profiles-daemon, causes USB HID autosuspend lag

  # Swapfile required for hibernate, must be >= RAM size (32 GB)
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

  # Fix WiFi and touchpad not working after suspend/resume.
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

        # Re-apply ALC295 mic fix in case the codec re-inits after resume
        sleep 2
        for codec in /proc/asound/card*/codec#*; do
          if grep -q "ALC295" "$codec" 2>/dev/null; then
            CARD=$(echo "$codec" | grep -oP 'card\K[0-9]+')
            ${pkgs.alsa-utils}/bin/amixer -c "$CARD" sset 'Mic Boost' 1
            ${pkgs.alsa-utils}/bin/amixer -c "$CARD" sset 'Capture' 25
            break
          fi
        done
      '';
    };
  };
}
