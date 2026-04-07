# Launcher Command Palette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fuzzel-based command palette (`Super+Space`) with prefix routing to calculator, web search, SSH, file search, emoji, color picker, wi-fi, pass, power menu, and LED matrix.

**Architecture:** All scripts are defined as `pkgs.writeShellScript` let-bindings in `modules/hyprland.nix`, following the existing `ledmatrixMenu` pattern. The top-level `palette` script composes them. Each sub-script is independently invokable. Keybindings wire everything into Hyprland.

**Tech Stack:** Nix, bash, fuzzel --dmenu, qalc (libqalculate), hyprpicker, nmcli (networkmanager), pass, wl-copy (wl-clipboard), notify-send (libnotify), fd, jq, bemoji, xdg-open

---

## File Map

- **Modify:** `modules/hyprland.nix` — add 10 writeShellScript let-bindings, update keybindings
- **Modify:** `modules/packages.nix` — add `libqalculate`, `hyprpicker`, `pass`, `wl-clipboard`

---

### Task 1: Add missing packages to packages.nix

**Files:**
- Modify: `modules/packages.nix`

- [ ] **Step 1: Add packages**

In `modules/packages.nix`, add to `home.packages = with pkgs; [` (after the existing `bemoji` entry in the QoL tools section):

```nix
    # Palette tools
    libqalculate   # qalc CLI: calculator + unit/currency converter
    hyprpicker     # color picker (Wayland)
    pass           # password manager
    wl-clipboard   # wl-copy / wl-paste
```

- [ ] **Step 2: Verify Nix syntax**

```bash
nix-instantiate --parse modules/packages.nix > /dev/null && echo ok
```

Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add modules/packages.nix
git commit -m "feat: add palette tool packages (qalc, hyprpicker, pass, wl-clipboard)"
```

---

### Task 2: Add palette sub-scripts to hyprland.nix

**Files:**
- Modify: `modules/hyprland.nix` — add 9 writeShellScript let-bindings after the `ledmatrixMenu` block (before the `in` keyword at line 152)

- [ ] **Step 1: Add the 9 sub-scripts**

Insert the following block in the `let` section of `modules/hyprland.nix`, after `ledmatrixMenu = ...` and before `in`:

```nix
  paletteWebSearch = pkgs.writeShellScript "palette-web-search" ''
    set -euo pipefail
    query="$1"
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
    entries=$(find "$STORE" -name "*.gpg" | sed "s|$STORE/||;s|\.gpg$||" | sort || true)
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
```

- [ ] **Step 2: Verify Nix syntax**

```bash
nix-instantiate --parse modules/hyprland.nix > /dev/null && echo ok
```

Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add modules/hyprland.nix
git commit -m "feat: add palette sub-scripts (web search, SSH, files, proc killer, color, wifi, pass, power, calc)"
```

---

### Task 3: Add the palette router script

**Files:**
- Modify: `modules/hyprland.nix` — add `palette` let-binding after `paletteCalc`

- [ ] **Step 1: Add the router**

Insert after `paletteCalc = ...` and before `in`:

```nix
  palette = pkgs.writeShellScript "palette" ''
    set -euo pipefail
    FUZZEL="${pkgs.fuzzel}/bin/fuzzel"

    input=$(printf '' | $FUZZEL --dmenu --prompt "  " || true)
    [ -z "$input" ] && exit 0

    prefix="''${input:0:1}"
    rest="''${input:1}"

    # Conversion pattern: "100 usd to eur", "10 km to miles"
    if printf '%s' "$input" | grep -qE '^[0-9]+\.?[0-9]*[[:space:]]+[^[:space:]]+[[:space:]]+to[[:space:]]+[^[:space:]]+$'; then
      ${paletteCalc} "$input"
      exit 0
    fi

    # Math pattern: starts with digit or ( and contains an operator
    if printf '%s' "$input" | grep -qE '^[0-9(]' && printf '%s' "$input" | grep -qE '[+*/^%]|[0-9]-[0-9]'; then
      ${paletteCalc} "$input"
      exit 0
    fi

    case "$prefix" in
      '?') ${paletteWebSearch} "$rest" ;;
      ':') ${pkgs.bemoji}/bin/bemoji -t ;;
      '@') ${paletteSSH} "$rest" ;;
      '/') ${paletteFiles} "$rest" ;;
      '>') ${paletteProcessKiller} "$rest" ;;
      '#') ${paletteColorPicker} ;;
      *)
        case "$input" in
          wifi)  ${paletteWifi} ;;
          pass)  ${palettePass} ;;
          power) ${palettePower} ;;
          led)   ${ledmatrixMenu} ;;
          *)     exec $FUZZEL --query "$input" ;;
        esac
        ;;
    esac
  '';
```

- [ ] **Step 2: Verify Nix syntax**

```bash
nix-instantiate --parse modules/hyprland.nix > /dev/null && echo ok
```

Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add modules/hyprland.nix
git commit -m "feat: add palette router script"
```

---

### Task 4: Update Hyprland keybindings

**Files:**
- Modify: `modules/hyprland.nix` — update `bind` list

- [ ] **Step 1: Replace the layout switcher binding and add new bindings**

In the `bind = [` list, replace:

```nix
        # Switch keyboard layout (DE ↔ Colemak-DH)
        "$mod, space, exec, hyprctl switchxkblayout all next"
```

With:

```nix
        # Palette
        "$mod, space, exec, ${palette}"
        "$mod SHIFT, space, exec, hyprctl switchxkblayout all next"
        "$mod SHIFT, P, exec, ${palettePower}"
        "$mod SHIFT, W, exec, ${paletteWifi}"
```

- [ ] **Step 2: Verify Nix syntax**

```bash
nix-instantiate --parse modules/hyprland.nix > /dev/null && echo ok
```

Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add modules/hyprland.nix
git commit -m "feat: wire palette and direct bindings into Hyprland keybindings"
```

---

### Task 5: Rebuild and verify

- [ ] **Step 1: Rebuild**

```bash
./setup.sh
```

Expected: build succeeds, no errors.

- [ ] **Step 2: Test palette opens**

Press `Super+Space`. Expected: fuzzel opens with `  ` prompt.

- [ ] **Step 3: Test calculator**

Type `2+2` in palette. Expected: notification shows `= 4`, `4` is in clipboard.

- [ ] **Step 4: Test conversion**

Type `100 usd to eur` in palette. Expected: notification shows result, result copied.

- [ ] **Step 5: Test web search**

Type `?nixos hyprland` in palette. Expected: zen-browser opens Google search.

- [ ] **Step 6: Test power menu**

Press `Super+Shift+P`. Expected: fuzzel shows Shutdown/Reboot/Suspend/Logout/Lock list.

- [ ] **Step 7: Test wi-fi selector**

Press `Super+Shift+W`. Expected: fuzzel shows available SSIDs.

- [ ] **Step 8: Test layout switcher moved**

Press `Super+Shift+Space`. Expected: keyboard layout switches (DE ↔ Colemak-DH).

- [ ] **Step 9: Test app launcher fallthrough**

Type `firefox` in palette without a prefix. Expected: native fuzzel opens with `firefox` pre-filled.

- [ ] **Step 10: Commit**

```bash
git add -p  # nothing to stage — all changes already committed
```

No additional commit needed if all tasks were committed per step.
