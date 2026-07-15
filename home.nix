{ config, pkgs, lib, user, ... }:

{
  imports = [
    ./modules/packages.nix
    ./modules/shell.nix
    ./modules/terminal.nix
    ./modules/waybar.nix
    ./modules/hyprland.nix
    ./modules/desktop.nix
    ./modules/services.nix
    ./modules/claude.nix
    ./modules/pi.nix
    ./modules/ai.nix
    ./modules/walker.nix
  ];

  home.username = user.username;
  home.homeDirectory = "/home/${user.username}";
  home.stateVersion = "24.11";

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

  # Suppress nixpkgs version mismatch warnings
  home.enableNixpkgsReleaseCheck = false;
}
