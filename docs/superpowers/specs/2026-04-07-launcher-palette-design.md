# Launcher Command Palette — Design Spec

Date: 2026-04-07

## Overview

Add a unified command palette (`Super+Space`) to the existing fuzzel-based launcher setup. The palette uses `fuzzel --dmenu` with prefix/pattern-based routing to different tools. Native fuzzel app launching (`Super+R`) and all existing keybindings stay unchanged.

## Routing Table

The palette script reads one line of input and routes based on prefix or pattern:

| Input | Routes to |
|---|---|
| `?<text>` | web search — opens zen-browser with the query |
| `:<text>` | emoji picker — invokes bemoji |
| `@<text>` | SSH — parses `~/.ssh/config` hosts, connects in kitty |
| `/<text>` | file search — fd from `$HOME`, opens result with xdg-open or kitty |
| `><text>` | process killer — ps list via fuzzel, kill on select |
| `#<text>` | color picker — hyprpicker, result copied to clipboard via wl-copy |
| `wifi` | wi-fi selector — nmcli list via fuzzel, nmcli connect on select |
| `pass` | password manager — pass list via fuzzel, selected password to wl-copy |
| `power` | power menu — shutdown/reboot/logout/suspend via fuzzel |
| `led` | LED matrix menu — invokes existing ledmatrixMenu script |
| math pattern (starts with digit, `(`, or known math token) | calculator — qalc evaluates and shows result via notify-send |
| conversion pattern (`<N> <unit> to <unit>`) | unit/currency converter — qalc evaluates and shows result via notify-send |
| anything else | falls through to native fuzzel app launcher |

Pattern detection for math vs conversion vs plain text:
- conversion: matches `^\d+\.?\d*\s+\S+\s+to\s+\S+`
- math: matches `^[\d(]` and contains an operator
- plain: everything else

## Keybindings

Changes to `modules/hyprland.nix`:

| Binding | Action | Change |
|---|---|---|
| `Super+Space` | command palette | new |
| `Super+Shift+Space` | keyboard layout switcher | moved from `Super+Space` |
| `Super+R` | native fuzzel app launcher | unchanged |
| `Super+V` | clipboard history (cliphist) | unchanged |
| `Super+.` (Period) | emoji picker (bemoji) | unchanged |
| `Super+Alt+G` | LED matrix menu | unchanged |
| `Super+Shift+P` | power menu | new direct binding |
| `Super+Shift+W` | wi-fi selector | new direct binding |

## Implementation

All scripts are defined as `pkgs.writeShellScript` in `modules/hyprland.nix`, following the existing pattern used for `ledmatrixMenu`. Each mode is its own `let` binding, then the palette script composes them.

Scripts:
- `paletteWebSearch` — xdg-open with browser search URL
- `paletteSSH` — parse `~/.ssh/config`, fuzzel pick, kitty -e ssh
- `paletteFiles` — fd search, fuzzel pick, xdg-open
- `paletteProcessKiller` — ps aux, fuzzel pick, kill
- `paletteColorPicker` — hyprpicker, wl-copy result
- `paletteWifi` — nmcli device wifi list, fuzzel pick, nmcli connect
- `palettePass` — pass ls, fuzzel pick, pass show -c
- `palettePower` — fuzzel pick from static list, dispatch systemctl/hyprctl
- `paletteCalc` — qalc expression, notify-send result
- `palette` — top-level router that calls the above

## Dependencies

| Package | Purpose | Likely present? |
|---|---|---|
| `qalc` (qalculate-gtk) | calculator + unit/currency conversion | no |
| `hyprpicker` | color picker | check |
| `networkmanager` | wi-fi via nmcli | likely yes |
| `pass` | password manager | check |
| `fd` | file search | yes |
| `bemoji` | emoji | yes |
| `wl-clipboard` | wl-copy for results | yes |
| `libnotify` | notify-send for calc results | yes |

Packages not already present get added to `modules/packages.nix`.
