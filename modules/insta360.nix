{ pkgs, ... }:

let
  installerVersion = "5.9.10";
  installerName = "Insta360_Studio_5.9.10_release_insta360(RC_build1)_20260616_181151_1781604939246.exe";
  installerStoreName = "Insta360_Studio_5.9.10_release_insta360-RC_build1-_20260616_181151_1781604939246.exe";
  installerSha256 = "b426b599624cf0bde2ba4442257b56329d2a375908af35a4cdd6ed6a188f6fbf";
  installerSha256SRI = "sha256-tCa1mWJM8L3iukRCJXtWMp0qN1kIrzWkzdbtahiPb78=";

  installer = pkgs.requireFile {
    name = installerName;
    sha256 = installerSha256;
    message = ''
      The official Insta360 Studio ${installerVersion} installer is not in the Nix store.
      Its downloaded filename contains parentheses, so copy it to a Nix-safe temporary
      filename before adding it with the legacy command supported by this installation:

        tmpdir="$(mktemp -d)"
        trap 'rm -rf "$tmpdir"' EXIT
        cp --reflink=auto \
          '/home/jymdo/Downloads/${installerName}' \
          "$tmpdir/${installerStoreName}"
        nix-store --add-fixed sha256 "$tmpdir/${installerStoreName}"

      The file must have SHA-256:
        Hex: ${installerSha256}
        SRI: ${installerSha256SRI}
    '';
  };

  insta360-studio = pkgs.writeShellScriptBin "insta360-studio" ''
    set -euo pipefail

    prefix="''${XDG_DATA_HOME:-$HOME/.local/share}/wineprefixes/insta360-studio"
    wine="${pkgs.wineWow64Packages.stagingFull}/bin/wine"
    installer="${installer}"

    find_studio() {
      ${pkgs.findutils}/bin/find "$prefix/drive_c" -type f \
        \( -iname 'Insta360 Studio.exe' -o -iname 'Insta360Studio.exe' \) \
        -print -quit 2>/dev/null || true
    }

    mkdir -p "$prefix"
    studio_exe="$(find_studio)"

    if [[ -z "$studio_exe" ]]; then
      echo "Insta360 Studio ${installerVersion} is not installed; starting the official installer."
      WINEPREFIX="$prefix" "$wine" "$installer"
      studio_exe="$(find_studio)"
      if [[ -z "$studio_exe" ]]; then
        echo "Insta360 Studio was not found in $prefix after installation." >&2
        exit 1
      fi
      echo "Insta360 Studio was installed. Run this launcher again to start it."
      exit 0
    fi

    export WINEPREFIX="$prefix"
    exec "$wine" "$studio_exe" "$@"
  '';
in
{
  home.packages = [ insta360-studio ];

  xdg.desktopEntries.insta360-studio = {
    name = "Insta360 Studio";
    comment = "Edit video with Insta360 Studio";
    exec = "insta360-studio %U";
    terminal = false;
    categories = [
      "AudioVideo"
      "AudioVideoEditing"
    ];
  };
}
