#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# NixOS FW16 AMD Setup Script
# ============================================================

VERSION="1.2.0"

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

# /tmp is always writable; survives crashes but not reboots (which is fine)
STATE_FILE="/tmp/nixos-setup-state"

RAW_BASE="https://raw.githubusercontent.com/JymD0/nix-conf/main"

# ============================================================
header "NixOS FW16 Setup"
echo -e "  ${BOLD}Version:${NC} ${GREEN}${VERSION}${NC}"
# ============================================================

# Must be run as root
[[ $EUID -ne 0 ]] && err "Please run as root: sudo bash setup.sh"

# ============================================================
header "Step 0: Fetch missing config files"
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for f in flake.nix configuration.nix home.nix; do
  if [[ ! -f "$SCRIPT_DIR/$f" ]]; then
    log "$f not found locally, downloading ..."
    curl -fsSL "$RAW_BASE/$f" -o "$SCRIPT_DIR/$f" \
      || err "Failed to download $f — are you connected to the internet?"
    log "  Downloaded $f"
  else
    log "  $f already present, skipping download."
  fi
done

# ============================================================
header "Step 1: Collect configuration values"
# ============================================================

if [[ -f "$STATE_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$STATE_FILE"
  warn "Loaded saved values from $STATE_FILE:"
  echo "  Hostname : $HOSTNAME"
  echo "  Username : $USERNAME"
  echo "  Full name: $FULLNAME"
  echo "  Email    : $EMAIL"
  echo ""
  read -rp "Use these saved values? [Y/n] " USE_SAVED
  if [[ "$USE_SAVED" =~ ^[Nn]$ ]]; then
    log "Re-entering values ..."
    rm -f "$STATE_FILE"
    unset HOSTNAME USERNAME FULLNAME EMAIL
  else
    log "Using saved values."
  fi
fi

# Only prompt for values that aren't already set
if [[ -z "${HOSTNAME:-}" ]]; then
  read -rp "$(echo -e "${BOLD}Hostname${NC} (e.g. fw16): ")" HOSTNAME
  [[ -z "$HOSTNAME" ]] && err "Hostname cannot be empty"
fi

if [[ -z "${USERNAME:-}" ]]; then
  read -rp "$(echo -e "${BOLD}Username${NC} (your login user): ")" USERNAME
  [[ -z "$USERNAME" ]] && err "Username cannot be empty"
fi

if [[ -z "${FULLNAME:-}" ]]; then
  read -rp "$(echo -e "${BOLD}Full name${NC} (for git, e.g. Jane Doe): ")" FULLNAME
  [[ -z "$FULLNAME" ]] && err "Full name cannot be empty"
fi

if [[ -z "${EMAIL:-}" ]]; then
  read -rp "$(echo -e "${BOLD}Email${NC} (for git & SSH key): ")" EMAIL
  [[ -z "$EMAIL" ]] && err "Email cannot be empty"
fi

# Persist to state file immediately after collection
cat > "$STATE_FILE" <<EOF
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
FULLNAME="$FULLNAME"
EMAIL="$EMAIL"
EOF
chmod 600 "$STATE_FILE"
log "Values saved to $STATE_FILE"

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
header "Step 5: Verify Nix is present"
# ============================================================

if ! nix --version &>/dev/null; then
  err "Nix not found. Is NixOS installed?"
fi

log "Nix found: $(nix --version)"

# ============================================================
header "Step 6: Build and switch"
# ============================================================

# NixOS manages users declaratively via users.users in configuration.nix.
# The rebuild below will create the user automatically - no useradd needed.
# NIX_CONFIG enables flakes for this single invocation.

# Clean old boot entries to prevent "No space left on device" on small EFI partitions
log "Cleaning old boot entries to free space on /boot ..."
find /boot/EFI/nixos/ -type f -delete 2>/dev/null || true
find /boot/loader/entries/ -type f -delete 2>/dev/null || true
nix-env --delete-generations +1 --profile /nix/var/nix/profiles/system 2>/dev/null || true
log "Boot partition cleaned."

log "Running nixos-rebuild switch (this will take a while) ..."
NIX_CONFIG="experimental-features = nix-command flakes" \
  nixos-rebuild switch --flake "/etc/nixos#$HOSTNAME"

# ============================================================
header "Step 7: Set user password"
# ============================================================

HOME_DIR="/home/$USERNAME"

if passwd -S "$USERNAME" 2>/dev/null | grep -q ' P '; then
  warn "Password already set for '$USERNAME', skipping."
else
  warn "Set a password for '$USERNAME':"
  passwd "$USERNAME"
fi

# ============================================================
header "Step 8: Create remaining home directories"
# ============================================================

# NOTE: .config is intentionally excluded - Home Manager owns it.
# xdg.userDirs.createDirectories in home.nix handles Desktop/Downloads/etc.
log "Creating extra home directories for $USERNAME ..."

EXTRA_DIRS=(
  ".local/bin"
  ".ssh"
)

for dir in "${EXTRA_DIRS[@]}"; do
  TARGET="$HOME_DIR/$dir"
  if [[ ! -d "$TARGET" ]]; then
    mkdir -p "$TARGET"
    log "  Created $TARGET"
  else
    warn "  Already exists: $TARGET"
  fi
done

chown -R "$USERNAME:users" "$HOME_DIR"
chmod 700 "$HOME_DIR/.ssh"
log "Ownership and permissions set."

# ============================================================
header "Step 9: Generate SSH key"
# ============================================================

SSH_KEY="$HOME_DIR/.ssh/id_ed25519"

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
header "Step 10: Install Claude Code"
# ============================================================

if command -v claude &>/dev/null || [[ -x "$HOME_DIR/.npm-global/bin/claude" ]]; then
  warn "Claude Code already installed, skipping."
else
  log "Configuring npm global prefix for $USERNAME ..."
  sudo -u "$USERNAME" mkdir -p "$HOME_DIR/.npm-global"
  sudo -u "$USERNAME" npm config set prefix "$HOME_DIR/.npm-global"

  log "Installing Claude Code via npm ..."
  sudo -u "$USERNAME" npm install -g @anthropic-ai/claude-code
  log "Claude Code installed. Run 'claude login' after reboot to authenticate."
fi

# Ensure ~/.npm-global/bin is on PATH via .profile
PROFILE="$HOME_DIR/.profile"
NPM_PATH_LINE='export PATH="$HOME/.npm-global/bin:$PATH"'
if ! grep -qF '.npm-global/bin' "$PROFILE" 2>/dev/null; then
  echo "$NPM_PATH_LINE" >> "$PROFILE"
  chown "$USERNAME:users" "$PROFILE"
  log "Added npm global bin to PATH in .profile"
fi

# ============================================================
header "All done!"
# ============================================================

# Clean up state file on successful completion
rm -f "$STATE_FILE"
log "State file removed (setup complete)."

echo ""
echo -e "${GREEN}${BOLD}Setup complete.${NC} Here's what to do next:"
echo ""
echo -e "  1. ${BOLD}Reboot${NC}              \u2192 sudo reboot"
echo -e "  2. ${BOLD}Log in${NC}              \u2192 via tuigreet, select Hyprland"
echo -e "  3. ${BOLD}Authenticate Claude${NC} \u2192 claude login"
echo -e "  4. ${BOLD}Copy SSH key${NC}        \u2192 ssh-copy-id <your-server>"
echo -e "  5. ${BOLD}Add SSH hosts${NC}       \u2192 edit /etc/nixos/home.nix (programs.ssh.matchBlocks)"
echo -e "                         then run: rebuild"
echo ""
warn "hardware-configuration.nix is machine-specific and not committed to the repo."
warn "Back it up manually if needed: cp /etc/nixos/hardware-configuration.nix ~/hardware-configuration.nix"
echo ""
