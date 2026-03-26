# User-specific settings — personalize these for your machine.
#
# After cloning, edit this file with your values, then run:
#   sudo nixos-rebuild switch --flake /etc/nixos#<your-hostname>
#
# To prevent git from tracking your local changes:
#   git update-index --skip-worktree user.nix
{
  # ── Identity ───────────────────────────────────────────────────────────────
  username = "yourUsername";
  hostname = "yourHostname";
  fullName = "Your Name";
  email    = "your.email@example.com";

  # ── Locale ─────────────────────────────────────────────────────────────────
  timezone       = "Europe/Vienna";
  locale         = "de_AT.UTF-8";
  keyboardLayout = "de";

  # ── SSH hosts ──────────────────────────────────────────────────────────────
  # Each key becomes a Host block in ~/.ssh/config.
  sshHosts = {
    # "myserver" = { hostname = "192.168.1.10"; user = "yourUsername"; };
  };

  # ── Calendar ───────────────────────────────────────────────────────────────
  # Default calendar name for khal (usually your Google email).
  defaultCalendar = "your.email@example.com";

  # Extra iCal calendar pairs for vdirsyncer.
  # URLs are fetched from GNOME Keyring by keyringAttr:
  #   secret-tool store --label='<name>' service vdirsyncer-ical attribute <keyringAttr>
  # ── MetaMCP ─────────────────────────────────────────────────────────────────
  # URL to your MetaMCP instance (used by the metamcp-proxy systemd service).
  metamcpUrl = "https://your-metamcp-instance.example.com/metamcp/Main/mcp";

  extraCalendars = {
    # "tiss" = { color = "#8be9fd"; keyringAttr = "tiss"; };
  };
}
