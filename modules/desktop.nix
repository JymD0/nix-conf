{ config, pkgs, lib, ... }:

{
  # ─── Variety setup (mutable files — variety needs chmod and write access) ────
  home.activation.varietySetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    variety_dir="$HOME/.config/variety"
    scripts_dir="$variety_dir/scripts"
    mkdir -p "$scripts_dir" "$variety_dir/Downloaded" "$variety_dir/Favorites" "$variety_dir/Fetched"

    # Only write config if not yet present (let variety manage it after first deploy)
    if [ ! -f "$variety_dir/variety.conf" ] || [ -L "$variety_dir/variety.conf" ]; then
      rm -f "$variety_dir/variety.conf"
      cat > "$variety_dir/variety.conf" << 'CONF'
# Wallpaper change settings
change_enabled = True
change_on_start = True
change_interval = 1800

# Download settings
download_enabled = True
download_interval = 60
download_folder = ~/.config/variety/Downloaded
quota_enabled = True
quota_size = 500

# Folders
favorites_folder = ~/.config/variety/Favorites
fetched_folder = ~/.config/variety/Fetched

# Image filtering
safe_mode = True
min_size_enabled = True
min_size = 80
use_landscape_enabled = True
lightness_enabled = False

[sources]
src1 = True|favorites|The Favorites folder
src2 = True|fetched|The Fetched folder
src3 = True|unsplash|High-resolution photos from Unsplash.com
src4 = True|bing|Bing Photo of the Day
src5 = True|wallhaven|nature dark
src6 = True|wallhaven|landscape
src7 = False|apod|NASA's Astronomy Picture of the Day
src8 = False|desktoppr|Random wallpapers from Desktoppr.co
src9 = False|earth|World Sunlight Map - live wallpaper from Die.net

[filters]
CONF
    fi

    cat > "$scripts_dir/set_wallpaper" << 'SCRIPT'
#!/bin/sh
if [ -z "$1" ]; then
  exit 1
fi
${pkgs.swww}/bin/swww img "$1" \
  --transition-type fade \
  --transition-duration 1 \
  --transition-fps 60
ln -sf "$1" "$HOME/.current-wallpaper"
SCRIPT
    chmod +x "$scripts_dir/set_wallpaper"

    cat > "$scripts_dir/get_wallpaper" << 'SCRIPT'
#!/bin/sh
${pkgs.swww}/bin/swww query | grep -oP 'image: \K.*' | head -1
SCRIPT
    chmod +x "$scripts_dir/get_wallpaper"

    cat > "$scripts_dir/set_lock_screen" << 'SCRIPT'
#!/bin/sh
exit 0
SCRIPT
    chmod +x "$scripts_dir/set_lock_screen"
  '';

  # ─── SwayOSD (on-screen display for volume/brightness) ────────────────────────
  services.swayosd = {
    enable = true;
    topMargin = 0.85;
    stylePath =
      let
        css = pkgs.writeText "swayosd-dracula.css" ''
          window#osd {
            padding: 12px 20px;
            border-radius: 14px;
            border: 2px solid rgba(189, 147, 249, 0.6);
            background-color: rgba(40, 42, 54, 0.92);
          }
          #container {
            margin: 6px;
          }
          image, label {
            color: #f8f8f2;
          }
          progressbar:disabled,
          image:disabled {
            opacity: 0.5;
          }
          progressbar {
            min-height: 6px;
            min-width: 0;
            border-radius: 999px;
            background: transparent;
            border: none;
          }
          trough {
            min-height: 6px;
            min-width: 0;
            border-radius: 999px;
            background-color: #44475a;
            border: none;
          }
          progress {
            min-height: 6px;
            min-width: 0;
            border-radius: 999px;
            background-color: #bd93f9;
            border: none;
          }
        '';
      in "${css}";
  };

  # ─── SwayNC (notification center) ──────────────────────────────────────────
  services.swaync = {
    enable = true;

    settings = {
      positionX = "right";
      positionY = "top";
      layer = "overlay";
      control-center-layer = "top";
      cssPriority = "application";

      notification-window-width = 360;
      notification-icon-size = 48;
      notification-body-image-height = 100;
      notification-body-image-width = 200;

      timeout = 8;
      timeout-low = 4;
      timeout-critical = 0;

      fit-to-screen = true;
      control-center-width = 400;
      control-center-height = 600;
      control-center-margin-top = 10;
      control-center-margin-bottom = 10;
      control-center-margin-right = 10;

      hide-on-clear = true;
      hide-on-action = true;

      scripts = {
        "notification-sound" = {
          exec = "canberra-gtk-play -i message-new-instant -d notification";
          app-name = ".*";
          run-on = "receive";
        };
      };

      widgets = [
        "title"
        "dnd"
        "notifications"
      ];

      widget-config = {
        title = {
          text = "Notifications";
          clear-all-button = true;
          button-text = "Clear All";
        };
        dnd = {
          text = "Do Not Disturb";
        };
      };
    };

    style = ''
      @define-color bg      rgba(40, 42, 54, 0.95);
      @define-color bg-solid #282a36;
      @define-color fg      #f8f8f2;
      @define-color comment #6272a4;
      @define-color purple  #bd93f9;
      @define-color pink    #ff79c6;
      @define-color cyan    #8be9fd;
      @define-color green   #50fa7b;
      @define-color red     #ff5555;
      @define-color yellow  #f1fa8c;
      @define-color orange  #ffb86c;
      @define-color current #44475a;

      * {
        font-family: "JetBrainsMono Nerd Font", "JetBrains Mono", monospace;
        font-size: 13px;
      }

      /* ── Notification popups ── */

      .notification-row {
        outline: none;
        background: transparent;
      }

      .notification-row:focus,
      .notification-row:hover {
        background: transparent;
      }

      .notification-row .notification-background {
        background: transparent;
      }

      .notification-group {
        background: transparent;
      }

      .notification-group:focus,
      .notification-group:hover {
        background: transparent;
      }

      .notification-group .notification-group-headers,
      .notification-group .notification-group-buttons {
        background: transparent;
      }

      .notification {
        background: @bg;
        border-radius: 12px;
        border: 2px solid @comment;
        margin: 4px 10px;
        padding: 0;
        box-shadow: 0 2px 12px rgba(0, 0, 0, 0.4);
      }

      .notification-content {
        padding: 10px 14px;
        color: @fg;
      }

      .notification .summary {
        font-weight: bold;
        color: @fg;
      }

      .notification .body {
        color: @comment;
      }

      .notification .time {
        color: @comment;
        font-size: 11px;
      }

      .notification:hover {
        border-color: @purple;
      }

      .critical .notification {
        border-color: @red;
      }

      .low .notification {
        border-color: @current;
      }

      /* ── Close button (hidden on popups) ── */
      .close-button {
        background: transparent;
        color: transparent;
        min-width: 0;
        min-height: 0;
        padding: 0;
        margin: 0;
        border: none;
      }

      /* ── Notification actions ── */
      .notification-action {
        background: @current;
        color: @fg;
        border-radius: 8px;
        border: none;
        margin: 4px;
        padding: 6px 12px;
      }
      .notification-action:hover {
        background: @purple;
        color: @bg-solid;
      }

      /* ── Control center ── */
      .control-center {
        background: @bg;
        border-radius: 14px;
        border: 2px solid rgba(98, 114, 164, 0.5);
        box-shadow: 0 4px 20px rgba(0, 0, 0, 0.5);
        margin: 8px;
        padding: 10px;
      }

      /* ── Title widget ── */
      .widget-title {
        color: @fg;
        font-weight: bold;
        font-size: 15px;
        margin: 6px 8px;
      }
      .widget-title > button {
        background: @current;
        color: @fg;
        border-radius: 8px;
        border: none;
        padding: 4px 12px;
        font-size: 12px;
      }
      .widget-title > button:hover {
        background: @red;
      }

      /* ── DND toggle ── */
      .widget-dnd {
        margin: 4px 8px;
        color: @fg;
      }
      .widget-dnd > switch {
        background: @current;
        border-radius: 12px;
        border: none;
      }
      .widget-dnd > switch:checked {
        background: @purple;
      }
      .widget-dnd > switch slider {
        background: @fg;
        border-radius: 10px;
        min-width: 16px;
        min-height: 16px;
      }

      /* ── Notifications in control center ── */
      .control-center .notification {
        margin: 4px 2px;
      }

      /* ── Progress bars (volume/brightness from apps) ── */
      progressbar {
        min-height: 6px;
      }
      trough {
        background: @current;
        border-radius: 999px;
        min-height: 6px;
      }
      progress {
        background: @purple;
        border-radius: 999px;
        min-height: 6px;
      }
    '';
  };

  # ─── Cursor Theme ─────────────────────────────────────────────────────────────
  home.pointerCursor = {
    name = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size = 24;
    gtk.enable = true;
  };

  # ─── Hyprlock ─────────────────────────────────────────────────────────────────
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        grace = 3;
      };

      background = [{
        path = "${config.home.homeDirectory}/.current-wallpaper";
        crossfade_time = 1.5;
      }];

      # ── Blurred box behind widgets ──────────────────────────────────────
      shape = [{
        size = "460, 440";
        color = "rgba(40, 42, 54, 0.55)";
        rounding = 24;
        blur_size = 6;
        blur_passes = 3;
        noise = 0.01;
        border_size = 2;
        border_color = "rgba(189, 147, 249, 0.25)";
        position = "0, 15";
        halign = "center";
        valign = "center";
      }];

      # ── Clock ──────────────────────────────────────────────────────────
      label = [
        {
          text = ''cmd[update:1000] echo "$(date +"%H:%M")"'';
          color = "rgba(248, 248, 242, 1.0)";
          font_size = 88;
          font_family = "JetBrains Mono ExtraBold";
          position = "0, 130";
          halign = "center";
          valign = "center";
          shadow_passes = 3;
          shadow_size = 6;
          shadow_color = "rgba(0, 0, 0, 0.5)";
        }
        # ── Date ─────────────────────────────────────────────────────────
        {
          text = ''cmd[update:60000] echo "$(LC_TIME=en_US.UTF-8 date +"%A, %d %B %Y")"'';
          color = "rgba(189, 147, 249, 1.0)";
          font_size = 16;
          font_family = "JetBrains Mono";
          position = "0, 40";
          halign = "center";
          valign = "center";
          shadow_passes = 2;
          shadow_size = 3;
          shadow_color = "rgba(0, 0, 0, 0.4)";
        }
        # ── User ─────────────────────────────────────────────────────────
        {
          text = "󰌾   $USER";
          color = "rgba(98, 114, 164, 1.0)";
          font_size = 13;
          font_family = "JetBrainsMono Nerd Font";
          position = "0, -40";
          halign = "center";
          valign = "center";
        }
      ];

      # ── Fingerprint ─────────────────────────────────────────────────────
      auth = {
        fingerprint = {
          enabled = true;
          ready_message = "Scan fingerprint to unlock";
          present_message = "Scanning…";
        };
      };

      # ── Password field ─────────────────────────────────────────────────
      input-field = [{
        size = "340, 50";
        outline_thickness = 2;
        dots_size = 0.22;
        dots_spacing = 0.35;
        outer_color = "rgb(189, 147, 249)";
        inner_color = "rgb(68, 71, 90)";
        font_color = "rgb(248, 248, 242)";
        check_color = "rgb(80, 250, 123)";
        fail_color = "rgb(255, 85, 85)";
        capslock_color = "rgb(241, 250, 140)";
        rounding = 12;
        fade_on_empty = false;
        placeholder_text = ''<span foreground="##6272a4">  Password</span>'';
        fail_text = ''<i>$FAIL  <b>($ATTEMPTS)</b></i>'';
        position = "0, -110";
        halign = "center";
        valign = "center";
      }];
    };
  };

  # ─── Hypridle ─────────────────────────────────────────────────────────────────
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on; hyprctl setcursor Bibata-Modern-Classic 24";
      };
      listener = [
        {
          timeout = 300;
          on-timeout = "brightnessctl -s set 30%";
          on-resume = "brightnessctl -r || brightnessctl set 100%";
        }
        {
          timeout = 600;
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 900;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        {
          timeout = 1800; # 30 min — suspend-then-hibernate when idle
          on-timeout = "systemctl suspend-then-hibernate";
        }
      ];
    };
  };

  # ─── Kanshi (display profiles) ───────────────────────────────────────────────
  services.kanshi = {
    enable = true;
    settings = [
      # Laptop screen only
      {
        profile.name = "laptop-only";
        profile.outputs = [{
          criteria = "eDP-1";
          status   = "enable";
        }];
      }

      # Any external monitor connected — Hyprland's auto-down rule places
      # eDP-1 below whatever external is active, regardless of its resolution.
      {
        profile.name = "docked";
        profile.outputs = [
          { criteria = "*";     status = "enable"; }
          { criteria = "eDP-1"; status = "enable"; }
        ];
        profile.exec = [ "sleep 1 && [ -L \"$HOME/.current-wallpaper\" ] && swww img \"$(readlink -f \"$HOME/.current-wallpaper\")\" --transition-type fade --transition-duration 1 --transition-fps 60" ];
      }
    ];
  };

  # ─── GTK ──────────────────────────────────────────────────────────────────────
  gtk = {
    enable = true;
    theme = {
      name    = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    gtk4.theme = config.gtk.theme;
    iconTheme = {
      name    = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };
}
