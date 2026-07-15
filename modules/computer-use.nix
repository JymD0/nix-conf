# Shared computer-use MCP server package.
# Imported by both claude.nix and codex.nix so the MCP server only gets
# defined once. Call with `import ./computer-use.nix { inherit pkgs; }`.
{ pkgs }:

pkgs.python3.pkgs.buildPythonApplication {
  pname = "computer-use";
  version = "0.1.0";
  src = ../scripts/computer-use;
  format = "pyproject";

  nativeBuildInputs = [
    pkgs.python3.pkgs.setuptools
    pkgs.gobject-introspection
    pkgs.wrapGAppsHook3
  ];

  propagatedBuildInputs = with pkgs.python3.pkgs; [
    mcp
    pillow
    pycairo
    pygobject3
  ];

  buildInputs = [
    pkgs.at-spi2-core
    pkgs.gtk4
    pkgs.gtk4-layer-shell
  ];

  # prevent wrapGAppsHook from double-wrapping (buildPythonApplication already wraps)
  dontWrapGApps = true;

  # merge GI typelib paths and runtime tools into the Python wrapper
  # LD_PRELOAD for gtk4-layer-shell: must load before libwayland-client
  preFixup = ''
    makeWrapperArgs+=(
      "''${gappsWrapperArgs[@]}"
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.grim
          pkgs.wtype
          pkgs.ydotool
          pkgs.wl-clipboard
          pkgs.hyprland
        ]
      }
      --set LD_PRELOAD ${pkgs.gtk4-layer-shell}/lib/libgtk4-layer-shell.so
      --set YDOTOOL_SOCKET /run/ydotoold/socket
    )
  '';

  doCheck = false;
}
