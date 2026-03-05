#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# NixOS FW16 AMD Setup Script
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log()     { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
err()     { echo -e "${RED}[x]${NC} $*"; exit 1; }
header()  { echo -e "\n${BOLD}${BLUE}==> $*${NC}"; }

# ============================================================
header "NixOS FW16 Setup"
# ============================================================

# Must be run as root
[[ $EUID -ne 0 ]] && err "Please run as root: sudo bash setup.sh"

# ============================================================
header "Step 1: Collect configuration values"
# ============================================================

read -rp "$(echo -e "${BOLD}Hostname${NC} (e.g. fw16): ")" HOSTNAME
[[ -z "$HOSTNAME" ]] && err "Hostname cannot be empty"

read -rp "$(echo -e "${BOLD}Username${NC} (your login user): ")" USERNAME
[[ -z "$USERNAME" ]] && err "Username cannot be empty"

read -rp "$(echo -e "${BOLD}Full name${NC} (for git, e.g. Jane Doe): ")" FULLNAME
[[ -z "$FULLNAME" ]] && err "Full name cannot be empty"

read -rp "$(echo -e "${BOLD}Email${NC} (for git & SSH key): ")" EMAIL
[[ -z "$EMAIL" ]] && err "Email cannot be empty"

echo ""
log "Will configure:"
echo "  Hostname : $HOSTNAME"
echo "  Username : $USERNAME"
echo "  Full name: $FULLNAME"
echo "  Email    : $EMAIL"
echo ""
read -rp "Continue? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || err "Aborted."

# ============================================================
header "Step 2: Copy config to /etc/nixos"
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$SCRIPT_DIR" != "/etc/nixos" ]]; then
  log "Copying config files to /etc/nixos ..."
  cp "$SCRIPT_DIR/flake.nix"         /etc/nixos/flake.nix
  cp "$SCRIPT_DIR/configuration.nix" /etc/nixos/configuration.nix
  cp "$SCRIPT_DIR/home.nix"          /etc/nixos/home.nix
else
  log "Already running from /etc/nixos, skipping copy."
fi

# ============================================================
header "Step 3: Replace placeholders"
# ============================================================

log "Substituting placeholders in config files ..."

sed -i \
  -e "s/yourHostname/$HOSTNAME/g" \
  -e "s/yourUsername/$USERNAME/g" \
  /etc/nixos/flake.nix

sed -i \
  -e "s/yourHostname/$HOSTNAME/g" \
  -e "s/yourUsername/$USERNAME/g" \
  /etc/nixos/configuration.nix

sed -i \
  -e "s/yourUsername/$USERNAME/g" \
  -e "s/Your Name/$FULLNAME/g" \
  -e "s/your\.email@example\.com/$EMAIL/g" \
  /etc/nixos/home.nix

log "Placeholders replaced."

# ============================================================
header "Step 4: Generate hardware configuration"
# ============================================================

if [[ -f /etc/nixos/hardware-configuration.nix ]]; then
  warn "hardware-configuration.nix already exists, skipping generation."
else
  log "Generating hardware-configuration.nix ..."
  nixos-generate-config --show-hardware-config > /etc/nixos/hardware-configuration.nix
  log "Generated."
fi

# ============================================================
header "Step 5: Enable flakes temporarily (if needed)"
# ============================================================

if ! nix --version &>/dev/null; then
  err "Nix not found. Is NixOS installed?"
fi

NIX_FLAGS="--extra-experimental-features 'nix-command flakes'"
log "Using experimental features flag for this build."

# ============================================================
header "Step 6: Build and switch"
# ============================================================

log "Running nixos-rebuild switch (this will take a while) ..."
nixos-rebuild switch \
  --extra-experimental-features 'nix-command flakes' \
  --flake "/etc/nixos#$HOSTNAME"

# ============================================================
header "Step 7: Create user if not exists"
# ============================================================

if id "$USERNAME" &>/dev/null; then
  log "User '$USERNAME' already exists."
else
  log "Creating user '$USERNAME' ..."
  useradd -m -G networkmanager,wheel,video,audio -s /bin/bash "$USERNAME"
  warn "Set a password for '$USERNAME':"
  passwd "$USERNAME"
fi

# ============================================================
header "Step 8: Generate SSH key"
# ============================================================

SSH_KEY="/home/$USERNAME/.ssh/id_ed25519"

if [[ -f "$SSH_KEY" ]]; then
  warn "SSH key already exists at $SSH_KEY, skipping."
else
  log "Generating ed25519 SSH key for $USERNAME ..."
  sudo -u "$USERNAME" ssh-keygen -t ed25519 -C "$EMAIL" -f "$SSH_KEY" -N ""
  log "SSH key generated."
  echo ""
  echo -e "${BOLD}Your public key (add to servers / GitHub):${NC}"
  cat "${SSH_KEY}.pub"
  echo ""
fi

# ============================================================
header "Step 9: Install Claude Code"
# ============================================================

if command -v claude &>/dev/null; then
  warn "Claude Code already installed, skipping."
else
  log "Installing Claude Code via npm ..."
  sudo -u "$USERNAME" npm install -g @anthropic-ai/claude-code
  log "Claude Code installed. Run 'claude login' after reboot to authenticate."
fi

# ============================================================
header "All done!"
# ============================================================

echo ""
echo -e "${GREEN}${BOLD}Setup complete.${NC} Here's what to do next:"
echo ""
echo -e "  1. ${BOLD}Reboot${NC}              → sudo reboot"
echo -e "  2. ${BOLD}Log in${NC}              → via tuigreet, select Hyprland"
echo -e "  3. ${BOLD}Authenticate Claude${NC} → claude login"
echo -e "  4. ${BOLD}Copy SSH key${NC}        → ssh-copy-id <your-server>"
echo -e "  5. ${BOLD}Add SSH hosts${NC}       → edit /etc/nixos/home.nix (programs.ssh.matchBlocks)"
echo -e "                         then run: rebuild"
echo ""
warn "hardware-configuration.nix is machine-specific and not committed to the repo."
warn "Back it up manually if needed: cp /etc/nixos/hardware-configuration.nix ~/hardware-configuration.nix"
echo ""
