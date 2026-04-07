{ pkgs, user, ... }:

let
  # Listen for Hyprland monitor-added events and re-apply wallpaper
  monitorWallpaperScript = pkgs.writeShellScript "monitor-wallpaper-sync" ''
    ${pkgs.socat}/bin/socat -U - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" |
      while IFS= read -r line; do
        case "$line" in
          monitoraddedv2*)
            sleep 1
            WP="$HOME/.current-wallpaper"
            if [ -L "$WP" ]; then
              ${pkgs.swww}/bin/swww img "$(readlink -f "$WP")" \
                --transition-type fade \
                --transition-duration 1 \
                --transition-fps 60
            fi
            ;;
        esac
      done
  '';

  # Send raw serial commands to the FW16 LED matrix module
  ledmatrixSend = pkgs.writeShellScript "ledmatrix-send" ''
    set -euo pipefail
    DEV="/dev/ttyACM0"
    stty -F "$DEV" 115200 raw -echo 2>/dev/null || true
    case "''$1:''$2" in
      start:snake)        printf '\x32\xac\x10\x00' > "$DEV" ;;
      start:pong)         printf '\x32\xac\x10\x01' > "$DEV" ;;
      start:tetris)       printf '\x32\xac\x10\x02' > "$DEV" ;;
      start:game-of-life) printf '\x32\xac\x10\x03' > "$DEV" ;;
      ctrl:up)            printf '\x32\xac\x11\x00' > "$DEV" ;;
      ctrl:down)          printf '\x32\xac\x11\x01' > "$DEV" ;;
      ctrl:left)          printf '\x32\xac\x11\x02' > "$DEV" ;;
      ctrl:right)         printf '\x32\xac\x11\x03' > "$DEV" ;;
      ctrl:exit)          printf '\x32\xac\x11\x04' > "$DEV" ;;
      *) exit 1 ;;
    esac
  '';

  # Fuzzel picker for LED matrix games, enters Hyprland submap on game start
  ledmatrixMenu = pkgs.writeShellScript "ledmatrix-menu" ''
    set -euo pipefail
    choice=$(printf "Snake\nPong\nTetris\nGame of Life\nStop" | ${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt "LED Matrix  " || true)
    [ -z "$choice" ] && exit 0
    case "$choice" in
      Snake)            ${ledmatrixSend} start snake ;;
      Pong)             ${ledmatrixSend} start pong ;;
      Tetris)           ${ledmatrixSend} start tetris ;;
      "Game of Life")   ${ledmatrixSend} start game-of-life ;;
      Stop)             ${ledmatrixSend} ctrl exit; exit 0 ;;
    esac
    hyprctl dispatch submap ledmatrix
  '';

in
{
  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = true;
    settings = {
      monitor = [
        # Laptop screen: always below any other monitor (auto-down is dynamic)
        "eDP-1,preferred,auto-down,1"
        # Any external monitor: top-left corner, preferred resolution
        ",preferred,0x0,1"
      ];

      exec-once = [
        "waybar"
        "hyprlock"
        "mkdir -p ~/.ssh/sockets" # for SSH ControlMaster multiplexing
        "gnome-keyring-daemon --start --components=secrets,ssh"
        "swww-daemon"
        "variety"
        "wl-paste --type text --watch cliphist store"
        "wl-paste --type image --watch cliphist store"
        # Re-apply wallpaper when a monitor is added (swww doesn't auto-sync new outputs)
        "${monitorWallpaperScript}"
      ];

      env = [
        "SSH_AUTH_SOCK,$XDG_RUNTIME_DIR/keyring/ssh" # GNOME Keyring SSH agent socket
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
        "TERMINAL,kitty"
        "AQ_MGPU_NO_EXPLICIT,1" # Workaround for eglDupNativeFenceFDANDROID crash on AMD Phoenix iGPU (#9746)
        "AQ_NO_ATOMIC,1"        # Disable atomic modesetting to prevent GPU fence crashes
      ];

      input = {
        kb_layout = "${user.keyboardLayout},us";
        kb_variant = ",colemak_dh_iso";
        follow_mouse = 1;
        sensitivity = 0;
        touchpad = {
          natural_scroll = true;
          disable_while_typing = true;
        };
      };

      cursor = {
        no_hardware_cursors = true;
        inactive_timeout = 0;
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
          size    = 8;
          passes  = 3;
          new_optimizations = true;
          xray = false;
        };
        shadow = {
          enabled = true;
          range   = 4;
          render_power = 3;
        };
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
          "specialWorkspace, 1, 6, default, slidevert"
          "layersIn, 1, 5, default, fade"
          "layersOut, 1, 5, default, fade"
        ];
      };

      misc = {
        disable_hyprland_logo    = true;
        disable_splash_rendering = true;
        force_default_wallpaper  = 0;
      };

      dwindle = {
        pseudotile    = true;
        preserve_split = true;
      };

      windowrule = [
        "float on, match:class ^(floating-calendar)$"
        "size 800 600, match:class ^(floating-calendar)$"
        "center on, match:class ^(floating-calendar)$"

        "float on, match:class ^(com.gabm.satty)$"
        "size 60% 70%, match:class ^(com.gabm.satty)$"
        "center on, match:class ^(com.gabm.satty)$"

        # Scratchpad terminal — slides up from bottom
        "float on, match:class ^(scratchpad)$"
        "size 80% 60%, match:class ^(scratchpad)$"
        "center on, match:class ^(scratchpad)$"
        "workspace special:scratchpad, match:class ^(scratchpad)$"
      ];

      layerrules = [
        "noanim, fuzzel"
      ];

      "$mod" = "SUPER";

      bind = [
        # Switch keyboard layout (DE ↔ Colemak-DH)
        "$mod, space, exec, hyprctl switchxkblayout all next"

        "$mod, Q, exec, kitty"
        "$mod, C, killactive,"
        "$mod, M, exit,"
        "$mod, E, exec, nemo"
        "$mod, V, exec, cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"
        "$mod, R, exec, fuzzel"
        "$mod, P, pseudo,"
        "$mod, O, togglesplit,"

        "$mod, B,       exec, zen-browser"
        "$mod SHIFT, D, exec, discord"
        "$mod SHIFT, C, exec, code"
        "$mod SHIFT, T, exec, kitty termscp"
        "$mod SHIFT, M, exec, nwg-displays"

        # Screenshots: grim → save + clipboard + notification (click to edit in satty)
        ''$mod, S,       exec, bash -c 'F=~/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png; mkdir -p ~/Pictures/Screenshots; grim -g "$(slurp)" "$F" && wl-copy < "$F" && { A=$(notify-send -a "Screenshot" -i "$F" "Screenshot saved" "$F" --action=default=Open) && [ "$A" = "default" ] && satty -f "$F"; } &' ''
        ''$mod SHIFT, S, exec, bash -c 'F=~/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png; mkdir -p ~/Pictures/Screenshots; grim "$F" && wl-copy < "$F" && { A=$(notify-send -a "Screenshot" -i "$F" "Screenshot saved" "$F" --action=default=Open) && [ "$A" = "default" ] && satty -f "$F"; } &' ''
        ''$mod ALT, S,   exec, bash -c 'F=~/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png; mkdir -p ~/Pictures/Screenshots; grim -g "$(hyprctl -j activewindow | jq -r '\"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\"')" "$F" && wl-copy < "$F" && { A=$(notify-send -a "Screenshot" -i "$F" "Screenshot saved" "$F" --action=default=Open) && [ "$A" = "default" ] && satty -f "$F"; } &' ''

        '', PRINT,       exec, bash -c 'F=~/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png; mkdir -p ~/Pictures/Screenshots; grim -g "$(slurp)" "$F" && wl-copy < "$F" && { A=$(notify-send -a "Screenshot" -i "$F" "Screenshot saved" "$F" --action=default=Open) && [ "$A" = "default" ] && satty -f "$F"; } &' ''
        ''$mod, PRINT,   exec, bash -c 'F=~/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png; mkdir -p ~/Pictures/Screenshots; grim "$F" && wl-copy < "$F" && { A=$(notify-send -a "Screenshot" -i "$F" "Screenshot saved" "$F" --action=default=Open) && [ "$A" = "default" ] && satty -f "$F"; } &' ''
        ''$mod SHIFT, PRINT, exec, bash -c 'F=~/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png; mkdir -p ~/Pictures/Screenshots; grim -g "$(hyprctl -j activewindow | jq -r '\"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\"')" "$F" && wl-copy < "$F" && { A=$(notify-send -a "Screenshot" -i "$F" "Screenshot saved" "$F" --action=default=Open) && [ "$A" = "default" ] && satty -f "$F"; } &' ''

        "$mod, X, togglefloating,"
        "$mod, Period, exec, bemoji -t"
        "$mod ALT, G, exec, ${ledmatrixMenu}"

        "$mod, F, fullscreen, 0"
        "$mod SHIFT, F, fullscreen, 1"
        "$mod, TAB, workspace, previous"
        "$mod, G, togglespecialworkspace, magic"
        "$mod SHIFT, G, movetoworkspace, special:magic"

        # Scratchpad terminal — toggle with Super+- (respawn if closed)
        "$mod, minus, exec, bash -c 'if hyprctl clients -j | jq -e \".[].class\" | grep -q scratchpad; then hyprctl dispatch togglespecialworkspace scratchpad; else kitty --class scratchpad; fi'"

        "$mod, Escape, exec, hyprlock"
        "$mod SHIFT, V, centerwindow,"

        "$mod, left,  movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up,    movefocus, u"
        "$mod, down,  movefocus, d"
        "$mod, H, movefocus, l"
        "$mod, J, movefocus, d"
        "$mod, K, movefocus, u"
        "$mod, L, movefocus, r"

        "$mod SHIFT, left,  movewindow, l"
        "$mod SHIFT, right, movewindow, r"
        "$mod SHIFT, up,    movewindow, u"
        "$mod SHIFT, down,  movewindow, d"
        "$mod SHIFT, H, movewindow, l"
        "$mod SHIFT, J, movewindow, d"
        "$mod SHIFT, K, movewindow, u"
        "$mod SHIFT, L, movewindow, r"

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

        "$mod, mouse_down, workspace, e+1"
        "$mod, mouse_up,   workspace, e-1"
      ];

      binde = [
        "$mod CTRL, left,  resizeactive, -20 0"
        "$mod CTRL, right, resizeactive, 20 0"
        "$mod CTRL, up,    resizeactive, 0 -20"
        "$mod CTRL, down,  resizeactive, 0 20"
        "$mod CTRL, H, resizeactive, -20 0"
        "$mod CTRL, J, resizeactive, 0 20"
        "$mod CTRL, K, resizeactive, 0 -20"
        "$mod CTRL, L, resizeactive, 20 0"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      bindel = [
        ", XF86AudioRaiseVolume, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume raise"
        ", XF86AudioLowerVolume, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume lower"
        ", XF86MonBrightnessUp, exec, ${pkgs.swayosd}/bin/swayosd-client --brightness raise"
        ", XF86MonBrightnessDown, exec, ${pkgs.swayosd}/bin/swayosd-client --brightness lower"
      ];
      bindl = [
        ", XF86AudioMute, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume mute-toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"
      ];

    };
    extraConfig = ''
      submap = ledmatrix
      bind = , up, exec, ${ledmatrixSend} ctrl up
      bind = , down, exec, ${ledmatrixSend} ctrl down
      bind = , left, exec, ${ledmatrixSend} ctrl left
      bind = , right, exec, ${ledmatrixSend} ctrl right
      bind = , w, exec, ${ledmatrixSend} ctrl up
      bind = , s, exec, ${ledmatrixSend} ctrl down
      bind = , a, exec, ${ledmatrixSend} ctrl left
      bind = , d, exec, ${ledmatrixSend} ctrl right
      bind = , escape, exec, ${ledmatrixSend} ctrl exit
      bind = , escape, submap, reset
      submap = reset
    '';
  };
}
