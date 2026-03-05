# NixOS Configuration — Framework 16 AMD

Declarative NixOS configuration managed with [Nix Flakes](https://nixos.wiki/wiki/Flakes) and [Home Manager](https://github.com/nix-community/home-manager).

## Setup

### 1. Clone this repo
```bash
sudo git clone https://github.com/JymD0/nix-conf /etc/nixos
```

### 2. Generate hardware config
```bash
sudo nixos-generate-config --show-hardware-config > /etc/nixos/hardware-configuration.nix
```

### 3. Edit placeholders
- `flake.nix` — replace `yourHostname` and `yourUsername`
- `configuration.nix` — replace `yourHostname` and `yourUsername`
- `home.nix` — replace `yourUsername`, git name/email, SSH hosts

### 4. Apply
```bash
sudo nixos-rebuild switch --flake /etc/nixos#yourHostname
```

### 5. Install Claude Code (after rebuild)
```bash
npm install -g @anthropic-ai/claude-code
claude login
```

### 6. Generate SSH key (optional but recommended)
```bash
ssh-keygen -t ed25519 -C "your.email@example.com"
ssh-copy-id your-server  # copies key to hosts defined in programs.ssh.matchBlocks
```

---

## Keybindings (Hyprland)

| Shortcut | Action |
|---|---|
| `Super + Q` | Open Kitty terminal |
| `Super + C` | Close window |
| `Super + R` | App launcher (fuzzel) |
| `Super + B` | Zen Browser |
| `Super + E` | File manager (Nemo) |
| `Super + X` | Clipboard history |
| `Super + .` | Emoji picker |
| `Super + Shift + T` | File transfer (termscp) |
| `Super + Shift + D` | Discord |
| `Super + Shift + C` | VS Code |
| `Print` | Screenshot area (copy) |
| `Super + Print` | Screenshot output (copy) |
| `Super + Shift + Print` | Screenshot area (save to ~/Pictures) |
| `Super + 1-0` | Switch workspace |
| `Super + Shift + 1-0` | Move window to workspace |
| `Super + Mouse drag` | Move window |
| `Super + Right-click drag` | Resize window |

---

## Structure

```
/etc/nixos/
├── flake.nix                  # Inputs and system definition
├── configuration.nix          # System-level config (hardware, services)
├── home.nix                   # User-level config (apps, dotfiles, keybinds)
├── hardware-configuration.nix # Auto-generated — not in repo
└── README.md
```

## Update
```bash
update   # alias: nix flake update + nixos-rebuild switch
rebuild  # alias: nixos-rebuild switch
```
