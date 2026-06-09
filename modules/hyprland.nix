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
      start:snake)        inputmodule-control --serial-dev "$DEV" led-matrix --start-game snake ;;
      start:pong)         inputmodule-control --serial-dev "$DEV" led-matrix --start-game pong ;;
      start:game-of-life) inputmodule-control --serial-dev "$DEV" led-matrix --start-game game-of-life --game-param glider ;;
      ctrl:up)            printf '\x32\xac\x11\x00' > "$DEV" ;;
      ctrl:down)          printf '\x32\xac\x11\x01' > "$DEV" ;;
      ctrl:left)          printf '\x32\xac\x11\x02' > "$DEV" ;;
      ctrl:right)         printf '\x32\xac\x11\x03' > "$DEV" ;;
      ctrl:second-left)   printf '\x32\xac\x11\x05' > "$DEV" ;;
      ctrl:second-right)  printf '\x32\xac\x11\x06' > "$DEV" ;;
      ctrl:exit)
        printf '\x32\xac\x11\x04' > "$DEV"
        inputmodule-control --serial-dev "$DEV" led-matrix --percentage 0
        ;;
      *) exit 1 ;;
    esac
  '';

  # Scrolling ticker — slides a 5-char window through padded text as a loop
  ledmatrixScroll = pkgs.writeShellScript "ledmatrix-scroll" ''
    set -euo pipefail
    DEV="/dev/ttyACM0"
    PIDFILE="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-scroll.pid"
    echo $$ > "$PIDFILE"
    trap 'rm -f "$PIDFILE"' EXIT

    text=$(echo "$1" | tr '[:lower:]' '[:upper:]')
    delay="''${2:-0.25}"
    padded="     ''${text}     "
    len=''${#padded}

    while true; do
      i=0
      while [ "$i" -le $((len - 5)) ]; do
        inputmodule-control --serial-dev "$DEV" led-matrix --string "''${padded:$i:5}"
        sleep "$delay"
        i=$((i + 1))
      done
    done
  '';

  # Duplicate the focused window; for kitty, open in the same working directory
  duplicateWindow = pkgs.writeShellScript "duplicate-window" ''
    set -euo pipefail
    win=$(hyprctl activewindow -j)
    class=$(echo "$win" | jq -r '.class // empty')
    pid=$(echo "$win" | jq -r '.pid // empty')
    [ -z "$class" ] || [ -z "$pid" ] && exit 0

    if [ "$class" = "kitty" ]; then
      cwd=$({ kitty @ --to "unix:/tmp/kitty-$pid" ls 2>/dev/null || true; } \
        | jq -r '.[] | .tabs[] | select(.is_focused) | .windows[] | select(.is_focused) | .cwd // empty' \
        | head -1)
      [ -z "$cwd" ] && cwd="$HOME"
      kitty --working-directory "$cwd" &
    else
      exe=$(readlink -f /proc/$pid/exe 2>/dev/null || true)
      [ -n "$exe" ] && "$exe" &
    fi
  '';

  # Fuzzel picker for LED matrix — games enter submap, display modes exit immediately
  ledmatrixMenu = pkgs.writeShellScript "ledmatrix-menu" ''
    set -euo pipefail
    DEV="/dev/ttyACM0"
    FUZZEL="${pkgs.fuzzel}/bin/fuzzel"
    IC="inputmodule-control --serial-dev $DEV led-matrix"

    choice=$(printf "Snake\nPong\nGame of Life\nWeather\nMood\nText\nScroll\nRain\nEKG\nCells\nBounce\nCascade\nSpiral\nScan\nStop" | $FUZZEL --dmenu --prompt "LED Matrix  " || true)
    [ -z "$choice" ] && exit 0

    case "$choice" in
      Snake)          ${ledmatrixSend} start snake ;;
      Pong)           ${ledmatrixSend} start pong ;;
      "Game of Life")
        p=$(printf "Glider\nBlinker\nToad\nBeacon\nBeacon-Toad-Blinker\nPattern 1\nCurrent Matrix" | $FUZZEL --dmenu --prompt "GoL Pattern  " || true)
        [ -z "$p" ] && exit 0
        case "$p" in
          Glider)                PARAM="glider" ;;
          Blinker)               PARAM="blinker" ;;
          Toad)                  PARAM="toad" ;;
          Beacon)                PARAM="beacon" ;;
          "Beacon-Toad-Blinker") PARAM="beacon-toad-blinker" ;;
          "Pattern 1")           PARAM="pattern1" ;;
          "Current Matrix")      PARAM="current-matrix" ;;
          *) exit 0 ;;
        esac
        $IC --start-game game-of-life --game-param "$PARAM"
        exit 0
        ;;

      Weather)
        w=$(printf "Sun\nCloud\nSnow\nRain\nThunder" | $FUZZEL --dmenu --prompt "Weather  " || true)
        [ -z "$w" ] && exit 0
        case "$w" in
          Sun)     $IC --symbols sun ;;
          Cloud)   $IC --symbols cloud ;;
          Snow)    $IC --symbols snow ;;
          Rain)    $IC --symbols rain ;;
          Thunder) $IC --symbols thunder ;;
        esac
        exit 0
        ;;

      Mood)
        m=$(printf "Happy\nNeutral\nSad\nWink\nHeart" | $FUZZEL --dmenu --prompt "Mood  " || true)
        [ -z "$m" ] && exit 0
        case "$m" in
          Happy)   $IC --symbols ':)' ;;
          Neutral) $IC --symbols ':|' ;;
          Sad)     $IC --symbols ':(' ;;
          Wink)    $IC --symbols ';)' ;;
          Heart)   $IC --symbols heart ;;
        esac
        exit 0
        ;;

      Text)
        t=$(printf "" | $FUZZEL --dmenu --prompt "Text (5 chars): " || true)
        [ -z "$t" ] && exit 0
        $IC --string "$(echo "$t" | tr '[:lower:]' '[:upper:]')"
        exit 0
        ;;

      Scroll)
        t=$(printf "" | $FUZZEL --dmenu --prompt "Scroll text: " || true)
        [ -z "$t" ] && exit 0
        for _f in rain ekg automaton bounce cascade spiral scan scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          if [ -f "$_pf" ]; then
            _pid=$(cat "$_pf")
            pkill -P "$_pid" 2>/dev/null || true
            kill "$_pid" 2>/dev/null || true
          fi
        done
        ${ledmatrixScroll} "$t" &
        exit 0
        ;;

      Rain)
        for _f in rain ekg automaton bounce cascade spiral scan scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          if [ -f "$_pf" ]; then
            _pid=$(cat "$_pf")
            pkill -P "$_pid" 2>/dev/null || true
            kill "$_pid" 2>/dev/null || true
          fi
        done
        ledmatrix-rain --dev "$DEV" &
        exit 0
        ;;

      EKG)
        for _f in rain ekg automaton bounce cascade spiral scan scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          if [ -f "$_pf" ]; then
            _pid=$(cat "$_pf")
            pkill -P "$_pid" 2>/dev/null || true
            kill "$_pid" 2>/dev/null || true
          fi
        done
        ledmatrix-ekg --dev "$DEV" &
        exit 0
        ;;

      Cells)
        for _f in rain ekg automaton bounce cascade spiral scan scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          if [ -f "$_pf" ]; then
            _pid=$(cat "$_pf")
            pkill -P "$_pid" 2>/dev/null || true
            kill "$_pid" 2>/dev/null || true
          fi
        done
        ledmatrix-automaton --dev "$DEV" &
        exit 0
        ;;

      Bounce)
        for _f in rain ekg automaton bounce cascade spiral scan scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          if [ -f "$_pf" ]; then
            _pid=$(cat "$_pf")
            pkill -P "$_pid" 2>/dev/null || true
            kill "$_pid" 2>/dev/null || true
          fi
        done
        ledmatrix-bounce --dev "$DEV" &
        exit 0
        ;;

      Cascade)
        for _f in rain ekg automaton bounce cascade spiral scan scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          if [ -f "$_pf" ]; then
            _pid=$(cat "$_pf")
            pkill -P "$_pid" 2>/dev/null || true
            kill "$_pid" 2>/dev/null || true
          fi
        done
        ledmatrix-cascade --dev "$DEV" &
        exit 0
        ;;

      Spiral)
        for _f in rain ekg automaton bounce cascade spiral scan scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          if [ -f "$_pf" ]; then
            _pid=$(cat "$_pf")
            pkill -P "$_pid" 2>/dev/null || true
            kill "$_pid" 2>/dev/null || true
          fi
        done
        ledmatrix-spiral --dev "$DEV" &
        exit 0
        ;;

      Scan)
        for _f in rain ekg automaton bounce cascade spiral scan scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          if [ -f "$_pf" ]; then
            _pid=$(cat "$_pf")
            pkill -P "$_pid" 2>/dev/null || true
            kill "$_pid" 2>/dev/null || true
          fi
        done
        ledmatrix-scan --dev "$DEV" &
        exit 0
        ;;

      Stop)
        for _f in rain ekg automaton bounce cascade spiral scan scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          if [ -f "$_pf" ]; then
            _pid=$(cat "$_pf")
            pkill -P "$_pid" 2>/dev/null || true
            kill "$_pid" 2>/dev/null || true
          fi
        done
        ${ledmatrixSend} ctrl exit
        exit 0
        ;;
      *)    exit 0 ;;
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
        "hyprlock-led"
        "mkdir -p ~/.ssh/sockets" # for SSH ControlMaster multiplexing
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
        "GTK_A11Y,atspi"            # expose GTK4 accessibility tree via AT-SPI2
        "QT_ACCESSIBILITY,1"        # expose Qt accessibility tree via AT-SPI2
        "GNOME_ACCESSIBILITY,1"     # expose Firefox/Zen accessibility tree via AT-SPI2
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

      # flat accel for ydotool so absolute mouse moves land at correct coordinates
      device = {
        name = "ydotoold-virtual-device-1";
        accel_profile = "flat";
        sensitivity = 0;
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
        "noanim, namespace:fuzzel"
        "animation off, namespace:fuzzel"
      ];

      "$mod" = "SUPER";

      bind = [
        "$mod, space, exec, walker"
        # Keyboard layout (DE ↔ Colemak-DH)
        "$mod SHIFT, space, exec, hyprctl switchxkblayout all next"

        "$mod, Q, exec, kitty"
        "$mod, D, exec, ${duplicateWindow}"
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

        # toggle computer use abort (lock file + overlay socket notification)
        "$mod, Escape, exec, computer-use-toggle"

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

        "$mod, L, exec, hyprlock-led"
        "$mod SHIFT, V, centerwindow,"

        "$mod, left,  movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up,    movefocus, u"
        "$mod, down,  movefocus, d"
        "$mod, H, movefocus, l"
        "$mod, J, movefocus, d"
        "$mod, K, movefocus, u"

        "$mod SHIFT, left,  movewindow, l"
        "$mod SHIFT, right, movewindow, r"
        "$mod SHIFT, up,    movewindow, u"
        "$mod SHIFT, down,  movewindow, d"
        "$mod SHIFT, H, movewindow, l"
        "$mod SHIFT, J, movewindow, d"
        "$mod SHIFT, K, movewindow, u"

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
      bind = , comma, exec, ${ledmatrixSend} ctrl second-left
      bind = , period, exec, ${ledmatrixSend} ctrl second-right
      bind = , escape, exec, ${ledmatrixSend} ctrl exit
      bind = , escape, submap, reset
      submap = reset
    '';
  };

  # Tools menu — lives here so it can reference ledmatrixMenu's store path
  xdg.configFile."elephant/menus/tools.toml".text = ''
    name = "tools"
    name_pretty = "Tools"

    [[entries]]
    text = "Color Picker"
    keywords = ["color", "eyedropper", "hex", "pick"]
    actions = { run = "sh -c 'c=$(hyprpicker); [ -n \"$c\" ] && printf \"%s\" \"$c\" | wl-copy && notify-send Color \"$c\" -t 2000'" }

    [[entries]]
    text = "Emoji Picker"
    keywords = ["emoji", "emoticon", "sticker"]
    actions = { run = "bemoji -t" }

    [[entries]]
    text = "Sunshine"
    keywords = ["sunshine", "remote", "stream", "moonlight"]
    actions = { run = "xdg-open https://localhost:47990" }

    [[entries]]
    text = "LED Matrix"
    keywords = ["led", "matrix", "animation", "effects"]
    actions = { run = "${ledmatrixMenu}" }
  '';
}
