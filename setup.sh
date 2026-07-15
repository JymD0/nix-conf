#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# NixOS Setup Script
# ============================================================

VERSION="1.4.0"

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

# ── Detect values already applied to /etc/nixos/user.nix ──────────────────────
detect_current_values() {
  local user="/etc/nixos/user.nix"
  DETECTED_HOSTNAME="" DETECTED_USERNAME="" DETECTED_FULLNAME="" DETECTED_EMAIL=""
  DETECTED_TIMEZONE="" DETECTED_LOCALE="" DETECTED_KEYBOARD="" DETECTED_HARDWARE=""
  DETECTED_WINDOWS_UUID="" DETECTED_SSH_HOSTS=""

  if [[ -f "$user" ]]; then
    local h u f e tz lc kb hw wu
    h=$(grep -oP '^\s*hostname\s*=\s*"\K[^"]+' "$user" 2>/dev/null | head -1)
    u=$(grep -oP 'username\s*=\s*"\K[^"]+' "$user" 2>/dev/null || true)
    f=$(grep -oP 'fullName\s*=\s*"\K[^"]+' "$user" 2>/dev/null || true)
    e=$(grep -oP 'email\s*=\s*"\K[^"]+' "$user" 2>/dev/null || true)
    tz=$(grep -oP 'timezone\s*=\s*"\K[^"]+' "$user" 2>/dev/null || true)
    lc=$(grep -oP 'locale\s*=\s*"\K[^"]+' "$user" 2>/dev/null || true)
    kb=$(grep -oP 'keyboardLayout\s*=\s*"\K[^"]+' "$user" 2>/dev/null || true)
    hw=$(grep -oP 'hardware\s*=\s*"\K[^"]+' "$user" 2>/dev/null || true)
    wu=$(grep -oP 'windowsEfiUuid\s*=\s*"\K[^"]+' "$user" 2>/dev/null || true)
    [[ "$h" != "yourHostname" ]]             && DETECTED_HOSTNAME="$h"  || true
    [[ "$u" != "yourUsername" ]]              && DETECTED_USERNAME="$u"  || true
    [[ "$f" != "Your Name"   ]]              && DETECTED_FULLNAME="$f"  || true
    [[ "$e" != "your.email@example.com" ]]   && DETECTED_EMAIL="$e"    || true
    [[ -n "$tz" && "$tz" != "UTC" ]]         && DETECTED_TIMEZONE="$tz"    || true
    [[ -n "$lc" && "$lc" != "en_US.UTF-8" ]] && DETECTED_LOCALE="$lc"     || true
    [[ -n "$kb" && "$kb" != "us" ]]          && DETECTED_KEYBOARD="$kb"    || true
    [[ -n "$hw" && "$hw" != "generic" ]]     && DETECTED_HARDWARE="$hw"    || true
    [[ -n "$wu" ]]                           && DETECTED_WINDOWS_UUID="$wu" || true
    # preserve the entire sshHosts block (brace-counted extraction)
    local ssh_block
    ssh_block=$(awk '
      /sshHosts\s*=\s*\{/ { found=1; depth=0 }
      found {
        for (i=1; i<=length($0); i++) {
          c = substr($0,i,1)
          if (c == "{") depth++
          if (c == "}") depth--
        }
        print
        if (depth == 0) exit
      }
    ' "$user" 2>/dev/null || true)
    # only preserve if it has actual host entries (not just empty braces)
    if [[ -n "$ssh_block" ]] && ! echo "$ssh_block" | grep -qP '^\s*sshHosts\s*=\s*\{\s*\}\s*;\s*$'; then
      DETECTED_SSH_HOSTS="$ssh_block"
    fi
  fi
}

# ============================================================
header "NixOS Setup"
echo -e "  ${BOLD}Version:${NC} ${GREEN}${VERSION}${NC}"
# ============================================================

# Must be run as root
[[ $EUID -ne 0 ]] && err "Please run as root: sudo bash setup.sh"

# ============================================================
header "Step 0: Fetch missing config files"
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for f in flake.nix configuration.nix home.nix user.nix; do
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

# Use SETUP_ prefix to avoid shadowing shell builtins (HOSTNAME, USERNAME)

# ── 1a. State-file shortcut (survives mid-run crashes) ────────────────────────
if [[ -f "$STATE_FILE" ]]; then
  # Validate ownership — /tmp is world-writable, so a non-root user could
  # plant a malicious state file before root runs this script.
  if [[ "$(stat -c %u "$STATE_FILE")" != "0" ]]; then
    warn "State file not owned by root, ignoring."
    rm -f "$STATE_FILE"
  fi
fi
if [[ -f "$STATE_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$STATE_FILE"
  warn "Loaded saved values from $STATE_FILE:"
  echo "  Hostname : $SETUP_HOSTNAME"
  echo "  Username : $SETUP_USERNAME"
  echo "  Full name: $SETUP_FULLNAME"
  echo "  Email    : $SETUP_EMAIL"
  echo "  Timezone : ${SETUP_TIMEZONE:-}"
  echo "  Locale   : ${SETUP_LOCALE:-}"
  echo "  Keyboard : ${SETUP_KEYBOARD:-}"
  echo "  Hardware : ${SETUP_HARDWARE:-}"
  echo "  Windows  : ${SETUP_WINDOWS_UUID:-(none)}"
  echo ""
  read -rp "Use these saved values? [Y/n] " USE_SAVED
  if [[ "$USE_SAVED" =~ ^[Nn]$ ]]; then
    log "Re-entering values ..."
    rm -f "$STATE_FILE"
    unset SETUP_HOSTNAME SETUP_USERNAME SETUP_FULLNAME SETUP_EMAIL \
          SETUP_TIMEZONE SETUP_LOCALE SETUP_KEYBOARD SETUP_HARDWARE SETUP_WINDOWS_UUID
  else
    log "Using saved values."
  fi
fi

# ── 1b. Current-values shortcut (already-configured install) ─────────────────
if [[ -z "${SETUP_HOSTNAME:-}" ]]; then
  detect_current_values
  if [[ -n "$DETECTED_HOSTNAME" && -n "$DETECTED_USERNAME" \
     && -n "$DETECTED_FULLNAME" && -n "$DETECTED_EMAIL" ]]; then
    SETUP_HOSTNAME="$DETECTED_HOSTNAME"
    SETUP_USERNAME="$DETECTED_USERNAME"
    SETUP_FULLNAME="$DETECTED_FULLNAME"
    SETUP_EMAIL="$DETECTED_EMAIL"
    [[ -n "$DETECTED_TIMEZONE" ]]     && SETUP_TIMEZONE="$DETECTED_TIMEZONE"
    [[ -n "$DETECTED_LOCALE" ]]       && SETUP_LOCALE="$DETECTED_LOCALE"
    [[ -n "$DETECTED_KEYBOARD" ]]     && SETUP_KEYBOARD="$DETECTED_KEYBOARD"
    [[ -n "$DETECTED_HARDWARE" ]]     && SETUP_HARDWARE="$DETECTED_HARDWARE"
    [[ -n "$DETECTED_WINDOWS_UUID" ]] && SETUP_WINDOWS_UUID="$DETECTED_WINDOWS_UUID"
    log "Using existing values from /etc/nixos/user.nix:"
    echo "  Hostname : $SETUP_HOSTNAME"
    echo "  Username : $SETUP_USERNAME"
    echo "  Full name: $SETUP_FULLNAME"
    echo "  Email    : $SETUP_EMAIL"
  fi
fi

# ── 1c. Individual prompts for any value still missing ────────────────────────
# Default hints show the detected value (if any) so the user can just press Enter.

prompt_with_default() {
  local label="$1" default="$2" var="$3"
  local hint=""
  [[ -n "$default" ]] && hint=" ${BLUE}[${default}]${NC}"
  read -rp "$(echo -e "${BOLD}${label}${NC}${hint}: ")" _val
  [[ -z "$_val" && -n "$default" ]] && _val="$default"
  printf -v "$var" '%s' "$_val"
}

if [[ -z "${SETUP_HOSTNAME:-}" ]]; then
  prompt_with_default "Hostname (e.g. fw16)" "${DETECTED_HOSTNAME:-}" SETUP_HOSTNAME
  [[ -z "$SETUP_HOSTNAME" ]] && err "Hostname cannot be empty"
  [[ "$SETUP_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] \
    || err "Invalid hostname: only letters, digits, and hyphens allowed"
fi

if [[ -z "${SETUP_USERNAME:-}" ]]; then
  prompt_with_default "Username (your login user)" "${DETECTED_USERNAME:-}" SETUP_USERNAME
  [[ -z "$SETUP_USERNAME" ]] && err "Username cannot be empty"
  [[ "$SETUP_USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] \
    || err "Invalid username: must start with a-z or _, then a-z 0-9 _ -"
fi

if [[ -z "${SETUP_FULLNAME:-}" ]]; then
  prompt_with_default "Full name (for git, e.g. Jane Doe)" "${DETECTED_FULLNAME:-}" SETUP_FULLNAME
  [[ -z "$SETUP_FULLNAME" ]] && err "Full name cannot be empty"
fi

if [[ -z "${SETUP_EMAIL:-}" ]]; then
  prompt_with_default "Email (for git & SSH key)" "${DETECTED_EMAIL:-}" SETUP_EMAIL
  [[ -z "$SETUP_EMAIL" ]] && err "Email cannot be empty"
  [[ "$SETUP_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]] \
    || err "Invalid email format"
fi

if [[ -z "${SETUP_TIMEZONE:-}" ]]; then
  prompt_with_default "Timezone (e.g. Europe/Vienna, America/New_York)" "${DETECTED_TIMEZONE:-UTC}" SETUP_TIMEZONE
  [[ -z "$SETUP_TIMEZONE" ]] && err "Timezone cannot be empty"
fi

if [[ -z "${SETUP_LOCALE:-}" ]]; then
  prompt_with_default "Locale (e.g. en_US.UTF-8, de_AT.UTF-8)" "${DETECTED_LOCALE:-en_US.UTF-8}" SETUP_LOCALE
  [[ -z "$SETUP_LOCALE" ]] && err "Locale cannot be empty"
fi

if [[ -z "${SETUP_KEYBOARD:-}" ]]; then
  prompt_with_default "Keyboard layout (e.g. us, de, fr)" "${DETECTED_KEYBOARD:-us}" SETUP_KEYBOARD
  [[ -z "$SETUP_KEYBOARD" ]] && err "Keyboard layout cannot be empty"
fi

if [[ -z "${SETUP_HARDWARE:-}" ]]; then
  echo ""
  echo -e "${BOLD}Hardware profile:${NC}"
  echo "  1) framework  - Framework 16 AMD (power mgmt, fingerprint, LED matrix, suspend fixes)"
  echo "  2) generic    - Any other machine (no hardware-specific tweaks)"
  echo ""
  prompt_with_default "Choose [1/2]" "${DETECTED_HARDWARE:-2}" SETUP_HARDWARE
  case "$SETUP_HARDWARE" in
    1|framework) SETUP_HARDWARE="framework" ;;
    2|generic)   SETUP_HARDWARE="generic" ;;
    *) err "Invalid choice: pick 1 (framework) or 2 (generic)" ;;
  esac
fi

if [[ -z "${SETUP_WINDOWS_UUID+set}" ]]; then
  echo ""
  echo -e "${BOLD}Windows dual-boot:${NC} If you have Windows installed, enter the EFI partition UUID"
  echo "  for a GRUB chainloader entry. Find it with: blkid | grep EFI"
  echo "  Leave empty to skip."
  echo ""
  prompt_with_default "Windows EFI UUID (or empty to skip)" "${DETECTED_WINDOWS_UUID:-}" SETUP_WINDOWS_UUID
fi

# Persist to state file immediately after collection
cat > "$STATE_FILE" <<EOF
SETUP_HOSTNAME="$SETUP_HOSTNAME"
SETUP_USERNAME="$SETUP_USERNAME"
SETUP_FULLNAME="$SETUP_FULLNAME"
SETUP_EMAIL="$SETUP_EMAIL"
SETUP_TIMEZONE="$SETUP_TIMEZONE"
SETUP_LOCALE="$SETUP_LOCALE"
SETUP_KEYBOARD="$SETUP_KEYBOARD"
SETUP_HARDWARE="$SETUP_HARDWARE"
SETUP_WINDOWS_UUID="${SETUP_WINDOWS_UUID:-}"
EOF
chmod 600 "$STATE_FILE"
log "Values saved to $STATE_FILE"

echo ""
log "Will configure:"
echo "  Hostname : $SETUP_HOSTNAME"
echo "  Username : $SETUP_USERNAME"
echo "  Full name: $SETUP_FULLNAME"
echo "  Email    : $SETUP_EMAIL"
echo "  Timezone : $SETUP_TIMEZONE"
echo "  Locale   : $SETUP_LOCALE"
echo "  Keyboard : $SETUP_KEYBOARD"
echo "  Hardware : $SETUP_HARDWARE"
echo "  Windows  : ${SETUP_WINDOWS_UUID:-(none)}"
echo ""
read -rp "Continue? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || err "Aborted."

# ============================================================
header "Step 2: Copy config to /etc/nixos"
# ============================================================

if [[ "$SCRIPT_DIR" != "/etc/nixos" ]]; then
  log "Copying config files to /etc/nixos ..."
  cp "$SCRIPT_DIR/flake.nix"         /etc/nixos/flake.nix
  cp "$SCRIPT_DIR/flake.lock"        /etc/nixos/flake.lock
  cp "$SCRIPT_DIR/configuration.nix" /etc/nixos/configuration.nix
  cp "$SCRIPT_DIR/home.nix"          /etc/nixos/home.nix
  cp "$SCRIPT_DIR/user.nix"          /etc/nixos/user.nix
  rm -rf /etc/nixos/modules
  cp -r "$SCRIPT_DIR/modules"        /etc/nixos/modules
  if [[ -d "$SCRIPT_DIR/assets" ]]; then
    rm -rf /etc/nixos/assets
    cp -r "$SCRIPT_DIR/assets"       /etc/nixos/assets
  fi
  if [[ -d "$SCRIPT_DIR/scripts" ]]; then
    rm -rf /etc/nixos/scripts
    cp -r "$SCRIPT_DIR/scripts"      /etc/nixos/scripts
  fi
else
  log "Already running from /etc/nixos, skipping copy."
fi

# ============================================================
header "Step 3: Ensure /etc/nixos is a flake-ready git repo"
# ============================================================
# Nix flakes only see files tracked by git. Stage placeholder files
# first, then overwrite user.nix with real values (unstaged) so
# personal data never enters git.

if [[ ! -d /etc/nixos/.git ]]; then
  log "Initialising git repo in /etc/nixos ..."
  git -C /etc/nixos init
fi

# disable sparse-checkout if it got turned on (breaks git add)
if git -C /etc/nixos config --get core.sparseCheckout &>/dev/null; then
  git -C /etc/nixos sparse-checkout disable 2>/dev/null || true
  git -C /etc/nixos config --unset core.sparseCheckout 2>/dev/null || true
  git -C /etc/nixos config --unset core.sparseCheckoutCone 2>/dev/null || true
  rm -f /etc/nixos/.git/info/sparse-checkout
fi

log "Staging config files (with placeholder user.nix) ..."
git -C /etc/nixos add flake.nix flake.lock configuration.nix home.nix user.nix modules/ assets/ scripts/ 2>/dev/null || git -C /etc/nixos add flake.nix flake.lock configuration.nix home.nix user.nix modules/

# ============================================================
header "Step 4: Write user.nix with real values"
# ============================================================
# Overwrite the placeholder user.nix with real values.
# This stays unstaged — Nix reads the working tree for dirty repos.

log "Writing user-specific values to /etc/nixos/user.nix ..."

# if no sshHosts detected from existing config, try the repo copy
if [[ -z "${DETECTED_SSH_HOSTS:-}" ]]; then
  repo_ssh=$(awk '
    /sshHosts\s*=\s*\{/ { found=1; depth=0 }
    found {
      for (i=1; i<=length($0); i++) {
        c = substr($0,i,1)
        if (c == "{") depth++
        if (c == "}") depth--
      }
      print
      if (depth == 0) exit
    }
  ' "$SCRIPT_DIR/user.nix" 2>/dev/null || true)
  [[ -n "$repo_ssh" ]] && DETECTED_SSH_HOSTS="$repo_ssh"
fi
SETUP_SSH_HOSTS="${DETECTED_SSH_HOSTS:-sshHosts = \{\};}"

cat > /etc/nixos/user.nix <<EOF
{
  username = "$SETUP_USERNAME";
  hostname = "$SETUP_HOSTNAME";
  fullName = "$SETUP_FULLNAME";
  email    = "$SETUP_EMAIL";

  timezone       = "$SETUP_TIMEZONE";
  locale         = "$SETUP_LOCALE";
  keyboardLayout = "$SETUP_KEYBOARD";

  hardware       = "$SETUP_HARDWARE";
  windowsEfiUuid = "${SETUP_WINDOWS_UUID:-}";

  $SETUP_SSH_HOSTS

  defaultCalendar = "$SETUP_EMAIL";

  extraCalendars = {};
}
EOF

# Prevent git from tracking local changes to user.nix (personal data protection).
# The placeholder version stays in the commit history for flake visibility,
# but skip-worktree ensures git status/add never picks up the real values.
git -C /etc/nixos update-index --skip-worktree user.nix 2>/dev/null || true

log "user.nix written and marked skip-worktree (personal data stays out of git)."

# ============================================================
header "Step 5: Generate hardware configuration"
# ============================================================

if [[ -f /etc/nixos/hardware-configuration.nix ]]; then
  warn "hardware-configuration.nix already exists, skipping generation."
else
  log "Generating hardware-configuration.nix ..."
  nixos-generate-config --show-hardware-config > /etc/nixos/hardware-configuration.nix
  log "Generated."
fi

# Stage so the flake can see it (machine-specific, never pushed)
git -C /etc/nixos add hardware-configuration.nix
log "hardware-configuration.nix staged for flake."

# ============================================================
header "Step 6: Verify Nix is present"
# ============================================================

if ! nix --version &>/dev/null; then
  err "Nix not found. Is NixOS installed?"
fi

log "Nix found: $(nix --version)"

# ============================================================
header "Step 7: Build and switch"
# ============================================================

# NixOS manages users declaratively via users.users in configuration.nix.
# The rebuild below will create the user automatically - no useradd needed.
# NIX_CONFIG enables flakes for this single invocation.

# Clean old generations to free space on /boot (keep last 3 for rollback safety)
log "Cleaning old generations to free space on /boot ..."
nix-env --delete-generations +3 --profile /nix/var/nix/profiles/system 2>/dev/null || true
log "Old generations cleaned."

log "Running nixos-rebuild switch (this will take a while) ..."
NIX_CONFIG="experimental-features = nix-command flakes" \
  nixos-rebuild switch --flake "path:/etc/nixos#$SETUP_HOSTNAME"

# Pi and its packages are pinned in modules/pi.nix. npm provides the supported
# release artifact while Home Manager owns its configuration and wrapper.
PI_PREFIX="/home/$SETUP_USERNAME/.local/share/pi"
log "Installing Pi coding agent ..."
sudo -u "$SETUP_USERNAME" -H "/etc/profiles/per-user/$SETUP_USERNAME/bin/npm" \
  install --global --ignore-scripts --prefix "$PI_PREFIX" \
  @earendil-works/pi-coding-agent@0.80.7 \
  @firfi/huly-mcp@0.44.4 \
  firecrawl-mcp@3.22.3 \
  @playwright/cli@0.1.17

log "Installing declared Pi packages ..."
sudo -u "$SETUP_USERNAME" -H "$PI_PREFIX/bin/pi" update --extensions

# Pi skips versioned npm specs during updates, so reconcile this upgraded pin
# explicitly when setup is rerun on an existing installation.
sudo -u "$SETUP_USERNAME" -H "/etc/profiles/per-user/$SETUP_USERNAME/bin/npm" \
  install --silent --prefix "/home/$SETUP_USERNAME/.pi/agent/npm" \
  --save-exact @narumitw/pi-codex-usage@0.15.1

# The usage package detects quota windows from their reported duration. Keep
# reset countdowns in its compact status so the footer can show both values.
CODEX_USAGE_EXTENSION="/home/$SETUP_USERNAME/.pi/agent/npm/node_modules/@narumitw/pi-codex-usage/src/format.ts"
if [[ -f "$CODEX_USAGE_EXTENSION" ]] && ! grep -q 'formatResetRemaining' "$CODEX_USAGE_EXTENSION"; then
  sudo -u "$SETUP_USERNAME" -H "/etc/profiles/per-user/$SETUP_USERNAME/bin/node" \
    - "$CODEX_USAGE_EXTENSION" <<'NODE'
const fs = require("node:fs");
const path = process.argv[2];
let source = fs.readFileSync(path, "utf8");
const replacements = [
  [
    '${formatRemainingPercent(snapshot.primary)} ${formatWindowLabel(snapshot.primary, "5h", true)}',
    '${formatWindowLabel(snapshot.primary, "5h", true)} ${formatRemainingPercent(snapshot.primary)}${snapshot.primary.resetsAt ? `→${formatResetRemaining(snapshot.primary.resetsAt)}` : ""}',
  ],
  [
    '${formatRemainingPercent(snapshot.secondary)} ${formatWindowLabel(snapshot.secondary, "weekly", true)}',
    '${formatWindowLabel(snapshot.secondary, "weekly", true)} ${formatRemainingPercent(snapshot.secondary)}${snapshot.secondary.resetsAt ? `→${formatResetRemaining(snapshot.secondary.resetsAt)}` : ""}',
  ],
];
for (const [oldText, newText] of replacements) {
  if (!source.includes(oldText)) throw new Error(`Codex usage patch target not found: ${oldText}`);
  source = source.replace(oldText, newText);
}
const marker = "function formatReset(epochSeconds: number): string {";
const helper = [
  "function formatResetRemaining(epochSeconds: number): string {",
  "\tconst minutes = Math.max(0, Math.ceil((epochSeconds * 1000 - Date.now()) / 60_000));",
  "\tif (minutes >= 1_440) return `${Math.floor(minutes / 1_440)}d${Math.floor((minutes % 1_440) / 60)}h`;",
  "\tif (minutes >= 60) return `${Math.floor(minutes / 60)}h${minutes % 60}m`;",
  "\treturn `${minutes}m`;",
  "}",
  "",
].join("\n");
if (!source.includes(marker)) throw new Error("Codex usage reset formatter not found");
fs.writeFileSync(path, source.replace(marker, helper + marker));
NODE
fi

# Keep the pinned remote-pi package aligned with the lifecycle fixes declared
# in modules/pi/patch-remote-pi.cjs. Home Manager runs the same patcher on every
# rebuild; setup runs it here because package installation happens afterwards.
REMOTE_PI_EXTENSION="/home/$SETUP_USERNAME/.pi/agent/npm/node_modules/remote-pi/dist/index.js"
REMOTE_PI_PATCHER="/etc/nixos/modules/pi/patch-remote-pi.cjs"
if [[ -f "$REMOTE_PI_EXTENSION" ]]; then
  [[ -f "$REMOTE_PI_PATCHER" ]] || err "Missing remote-pi patcher: $REMOTE_PI_PATCHER"
  sudo -u "$SETUP_USERNAME" -H "/etc/profiles/per-user/$SETUP_USERNAME/bin/node" \
    "$REMOTE_PI_PATCHER" "$REMOTE_PI_EXTENSION"
fi

# ============================================================
header "Step 8: Set user password"
# ============================================================

HOME_DIR="/home/$SETUP_USERNAME"

if passwd -S "$SETUP_USERNAME" 2>/dev/null | grep -q ' P '; then
  warn "Password already set for '$SETUP_USERNAME', skipping."
else
  warn "Set a password for '$SETUP_USERNAME':"
  passwd "$SETUP_USERNAME"
fi

# ============================================================
header "Step 9: Create remaining home directories"
# ============================================================

# NOTE: .config is intentionally excluded - Home Manager owns it.
# xdg.userDirs.createDirectories in home.nix handles Desktop/Downloads/etc.
log "Creating extra home directories for $SETUP_USERNAME ..."

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

chown -R "$SETUP_USERNAME:users" "$HOME_DIR"
chmod 700 "$HOME_DIR/.ssh"
log "Ownership and permissions set."

# ============================================================
header "Step 10: Generate SSH key"
# ============================================================

SSH_KEY="$HOME_DIR/.ssh/id_ed25519"

if [[ -f "$SSH_KEY" ]]; then
  warn "SSH key already exists at $SSH_KEY, skipping."
else
  log "Generating ed25519 SSH key for $SETUP_USERNAME ..."
  sudo -u "$SETUP_USERNAME" ssh-keygen -t ed25519 -C "$SETUP_EMAIL" -f "$SSH_KEY" -N ""
  log "SSH key generated."
  echo ""
  echo -e "${BOLD}Your public key (add to servers / GitHub):${NC}"
  cat "${SSH_KEY}.pub"
  echo ""
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
echo -e "  2. ${BOLD}Authenticate Pi${NC}     \u2192 pi, then /login and select OpenAI ChatGPT Plus/Pro"
echo -e "  3. ${BOLD}Authenticate Claude${NC} \u2192 claude login"
echo -e "  4. ${BOLD}Copy SSH key${NC}        \u2192 ssh-copy-id <your-server>"
echo -e "  5. ${BOLD}Add SSH hosts${NC}       \u2192 edit /etc/nixos/user.nix (sshHosts)"
echo -e "                         then run: rebuild"
echo ""
warn "hardware-configuration.nix is machine-specific and not committed to the repo."
warn "Back it up manually if needed: cp /etc/nixos/hardware-configuration.nix ~/hardware-configuration.nix"
echo ""
