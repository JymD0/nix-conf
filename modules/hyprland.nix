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

  # Fuzzel picker for LED matrix — games enter submap, display modes exit immediately
  ledmatrixMenu = pkgs.writeShellScript "ledmatrix-menu" ''
    set -euo pipefail
    DEV="/dev/ttyACM0"
    FUZZEL="${pkgs.fuzzel}/bin/fuzzel"
    IC="inputmodule-control --serial-dev $DEV led-matrix"

    choice=$(printf "Snake\nPong\nGame of Life\nWeather\nMood\nText\nScroll\nFire\nPlasma\nRain\nMetaballs\nStarfield\nStop" | $FUZZEL --dmenu --prompt "LED Matrix  " || true)
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
        for _f in fire plasma rain metaballs starfield scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          [ -f "$_pf" ] && kill "$(cat "$_pf")" 2>/dev/null || true
        done
        ${ledmatrixScroll} "$t" &
        exit 0
        ;;

      Fire)
        for _f in fire plasma rain metaballs starfield scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          [ -f "$_pf" ] && kill "$(cat "$_pf")" 2>/dev/null || true
        done
        ledmatrix-fire --dev "$DEV" &
        exit 0
        ;;

      Plasma)
        for _f in fire plasma rain metaballs starfield scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          [ -f "$_pf" ] && kill "$(cat "$_pf")" 2>/dev/null || true
        done
        ledmatrix-plasma --dev "$DEV" &
        exit 0
        ;;

      Rain)
        for _f in fire plasma rain metaballs starfield scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          [ -f "$_pf" ] && kill "$(cat "$_pf")" 2>/dev/null || true
        done
        ledmatrix-rain --dev "$DEV" &
        exit 0
        ;;

      Metaballs)
        for _f in fire plasma rain metaballs starfield scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          [ -f "$_pf" ] && kill "$(cat "$_pf")" 2>/dev/null || true
        done
        ledmatrix-metaballs --dev "$DEV" &
        exit 0
        ;;

      Starfield)
        for _f in fire plasma rain metaballs starfield scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          [ -f "$_pf" ] && kill "$(cat "$_pf")" 2>/dev/null || true
        done
        ledmatrix-starfield --dev "$DEV" &
        exit 0
        ;;

      Stop)
        for _f in fire plasma rain metaballs starfield scroll; do
          _pf="''${XDG_RUNTIME_DIR:-/tmp}/ledmatrix-$_f.pid"
          [ -f "$_pf" ] && kill "$(cat "$_pf")" 2>/dev/null || true
        done
        ${ledmatrixSend} ctrl exit
        exit 0
        ;;
      *)    exit 0 ;;
    esac
    hyprctl dispatch submap ledmatrix
  '';

  paletteWebSearch = pkgs.writeShellScript "palette-web-search" ''
    set -euo pipefail
    FUZZEL="${pkgs.fuzzel}/bin/fuzzel"
    query="''${1:-}"
    if [ -z "$query" ]; then
      query=$(printf "search the web..." | $FUZZEL --dmenu --prompt "Search  " || true)
      [ "$query" = "search the web..." ] && exit 0
    fi
    [ -z "$query" ] && exit 0
    encoded=$(printf '%s' "$query" | ${pkgs.jq}/bin/jq -Rr @uri)
    ${pkgs.xdg-utils}/bin/xdg-open "https://www.google.com/search?q=$encoded"
  '';

  paletteSSH = pkgs.writeShellScript "palette-ssh" ''
    set -euo pipefail
    FUZZEL="${pkgs.fuzzel}/bin/fuzzel"
    filter="''${1:-}"
    hosts=$(grep -i "^Host " "$HOME/.ssh/config" 2>/dev/null | awk '{print $2}' | grep -v '[*?]' || true)
    [ -z "$hosts" ] && exit 0
    if [ -n "$filter" ]; then
      hosts=$(printf '%s' "$hosts" | grep -i "$filter" || true)
      [ -z "$hosts" ] && exit 0
    fi
    host=$(printf '%s' "$hosts" | $FUZZEL --dmenu --prompt "SSH  " || true)
    [ -z "$host" ] && exit 0
    ${pkgs.kitty}/bin/kitty -e ssh "$host"
  '';

  paletteFiles = pkgs.writeShellScript "palette-files" ''
    set -euo pipefail
    FUZZEL="${pkgs.fuzzel}/bin/fuzzel"
    query="''${1:-.}"
    results=$(${pkgs.fd}/bin/fd "$query" "$HOME" --max-results 50 2>/dev/null || true)
    [ -z "$results" ] && exit 0
    file=$(printf '%s' "$results" | $FUZZEL --dmenu --prompt "Open  " || true)
    [ -z "$file" ] && exit 0
    ${pkgs.xdg-utils}/bin/xdg-open "$file"
  '';

  paletteProcessKiller = pkgs.writeShellScript "palette-process-killer" ''
    set -euo pipefail
    FUZZEL="${pkgs.fuzzel}/bin/fuzzel"
    filter="''${1:-}"
    procs=$(ps -eo pid,comm,args --no-headers | grep -v "^ *$$ ")
    if [ -n "$filter" ]; then
      procs=$(printf '%s' "$procs" | grep -i "$filter" || true)
    fi
    [ -z "$procs" ] && exit 0
    sel=$(printf '%s' "$procs" | $FUZZEL --dmenu --prompt "Kill  " || true)
    [ -z "$sel" ] && exit 0
    pid=$(printf '%s' "$sel" | awk '{print $1}')
    kill "$pid" 2>/dev/null || true
    ${pkgs.libnotify}/bin/notify-send "Killed" "PID $pid" -t 2000
  '';

  paletteColorPicker = pkgs.writeShellScript "palette-color-picker" ''
    set -euo pipefail
    color=$(${pkgs.hyprpicker}/bin/hyprpicker 2>/dev/null || true)
    [ -z "$color" ] && exit 0
    printf '%s' "$color" | ${pkgs.wl-clipboard}/bin/wl-copy
    ${pkgs.libnotify}/bin/notify-send "Color copied" "$color" -t 2000
  '';

  paletteWifi = pkgs.writeShellScript "palette-wifi" ''
    set -euo pipefail
    FUZZEL="${pkgs.fuzzel}/bin/fuzzel"
    NMCLI="${pkgs.networkmanager}/bin/nmcli"
    networks=$($NMCLI -t -f SSID device wifi list 2>/dev/null | sort -u | grep -v '^--$' | grep -v '^$' || true)
    [ -z "$networks" ] && exit 0
    ssid=$(printf '%s' "$networks" | $FUZZEL --dmenu --prompt "WiFi  " || true)
    [ -z "$ssid" ] && exit 0
    $NMCLI device wifi connect "$ssid" \
      && ${pkgs.libnotify}/bin/notify-send "WiFi" "Connecting to $ssid" -t 3000 \
      || ${pkgs.libnotify}/bin/notify-send "WiFi" "Failed to connect to $ssid" -u normal -t 4000
  '';

  palettePass = pkgs.writeShellScript "palette-pass" ''
    set -euo pipefail
    FUZZEL="${pkgs.fuzzel}/bin/fuzzel"
    STORE="$HOME/.password-store"
    if [ ! -d "$STORE" ]; then
      ${pkgs.libnotify}/bin/notify-send "pass" "No password store found" -t 3000
      exit 0
    fi
    entries=$(${pkgs.findutils}/bin/find "$STORE" -name "*.gpg" | ${pkgs.gnused}/bin/sed "s|$STORE/||;s|\.gpg$||" | ${pkgs.coreutils}/bin/sort || true)
    [ -z "$entries" ] && exit 0
    entry=$(printf '%s' "$entries" | $FUZZEL --dmenu --prompt "Pass  " || true)
    [ -z "$entry" ] && exit 0
    ${pkgs.pass}/bin/pass show -c "$entry"
  '';

  palettePower = pkgs.writeShellScript "palette-power" ''
    set -euo pipefail
    FUZZEL="${pkgs.fuzzel}/bin/fuzzel"
    choice=$(printf "Shutdown\nReboot\nSuspend\nLogout\nLock" | $FUZZEL --dmenu --prompt "Power  " || true)
    [ -z "$choice" ] && exit 0
    case "$choice" in
      Shutdown) systemctl poweroff ;;
      Reboot)   systemctl reboot ;;
      Suspend)  systemctl suspend ;;
      Logout)   hyprctl dispatch exit ;;
      Lock)     ${pkgs.hyprlock}/bin/hyprlock ;;
    esac
  '';

  paletteCalc = pkgs.writeShellScript "palette-calc" ''
    set -euo pipefail
    expr="$*"
    result=$(${pkgs.libqalculate}/bin/qalc -t "$expr" 2>/dev/null | tail -1 || echo "error")
    printf '%s' "$result" | ${pkgs.wl-clipboard}/bin/wl-copy
    ${pkgs.libnotify}/bin/notify-send "= $result" "$expr" -t 4000
  '';

  palette = pkgs.writeShellScript "palette" ''
    set -euo pipefail
    FUZZEL="${pkgs.fuzzel}/bin/fuzzel"
    NMCLI="${pkgs.networkmanager}/bin/nmcli"

    items=$(
      printf "shutdown\nreboot\nsuspend\nlogout\nlock\n"
      printf "emoji\ncolor\nled\n"
      $NMCLI -t -f SSID device wifi list --rescan no 2>/dev/null \
        | sort -u | grep -v '^--$' | grep -v '^$' | sed 's/^/wifi  /' || true
      grep -i "^Host " "$HOME/.ssh/config" 2>/dev/null \
        | awk '{print $2}' | grep -v '[*?]' | sed 's/^/ssh  /' || true
      ps -eo comm,pid --no-headers 2>/dev/null \
        | sort -u | head -50 | awk '{printf "kill  %s (%s)\n", $1, $2}' || true
      if [ -d "$HOME/.password-store" ]; then
        ${pkgs.findutils}/bin/find "$HOME/.password-store" -name "*.gpg" \
          | sed "s|$HOME/.password-store/||;s|\.gpg$||" | sort | sed 's/^/pass  /' || true
      fi
    )

    sel=$(printf '%s' "$items" | $FUZZEL --dmenu --prompt "  " || true)
    [ -z "$sel" ] && exit 0

    case "$sel" in
      shutdown) systemctl poweroff ;;
      reboot)   systemctl reboot ;;
      suspend)  systemctl suspend ;;
      logout)   hyprctl dispatch exit ;;
      lock)     ${pkgs.hyprlock}/bin/hyprlock ;;
      emoji)    ${pkgs.bemoji}/bin/bemoji -t ;;
      color)
        c=$(${pkgs.hyprpicker}/bin/hyprpicker 2>/dev/null || true)
        [ -z "$c" ] && exit 0
        printf '%s' "$c" | ${pkgs.wl-clipboard}/bin/wl-copy
        ${pkgs.libnotify}/bin/notify-send "Color" "$c" -t 2000
        ;;
      led) ${ledmatrixMenu} ;;
      "wifi  "*)
        ssid="''${sel#wifi  }"
        $NMCLI device wifi connect "$ssid" \
          && ${pkgs.libnotify}/bin/notify-send "WiFi" "Connecting to $ssid" -t 3000 \
          || ${pkgs.libnotify}/bin/notify-send "WiFi" "Failed to connect" -u normal -t 4000
        ;;
      "ssh  "*)
        host="''${sel#ssh  }"
        ${pkgs.kitty}/bin/kitty -e ssh "$host"
        ;;
      "kill  "*)
        pid=$(printf '%s' "$sel" | grep -oE '\([0-9]+\)$' | tr -d '()')
        kill "$pid" 2>/dev/null || true
        ${pkgs.libnotify}/bin/notify-send "Killed" "''${sel#kill  }" -t 2000
        ;;
      "pass  "*)
        entry="''${sel#pass  }"
        ${pkgs.pass}/bin/pass show -c "$entry"
        ;;
      *)
        if printf '%s' "$sel" | grep -qE '^[0-9]+\.?[0-9]*[[:space:]]+[^[:space:]]+[[:space:]]+to[[:space:]]+[^[:space:]]+$'; then
          ${paletteCalc} "$sel"
        elif printf '%s' "$sel" | grep -qE '^[0-9(]' && printf '%s' "$sel" | grep -qE '[+*/^%]|[0-9]-[0-9]'; then
          ${paletteCalc} "$sel"
        else
          encoded=$(printf '%s' "$sel" | ${pkgs.jq}/bin/jq -Rr @uri)
          ${pkgs.xdg-utils}/bin/xdg-open "https://www.google.com/search?q=$encoded"
        fi
        ;;
    esac
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
        "noanim, namespace:fuzzel"
        "animation off, namespace:fuzzel"
      ];

      "$mod" = "SUPER";

      bind = [
        # Palette
        "$mod, space, exec, ${palette}"
        # Keyboard layout (DE ↔ Colemak-DH, moved from Super+Space)
        "$mod SHIFT, space, exec, hyprctl switchxkblayout all next"
        "$mod SHIFT, P, exec, ${palettePower}"
        "$mod SHIFT, W, exec, ${paletteWifi}"

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
      bind = , comma, exec, ${ledmatrixSend} ctrl second-left
      bind = , period, exec, ${ledmatrixSend} ctrl second-right
      bind = , escape, exec, ${ledmatrixSend} ctrl exit
      bind = , escape, submap, reset
      submap = reset
    '';
  };
}
