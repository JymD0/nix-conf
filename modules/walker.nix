{ pkgs, ... }:

{
  home.packages = with pkgs; [ walker elephant ];

  # Elephant must be running before walker connects to it
  systemd.user.services.elephant = {
    Unit = {
      Description = "Elephant provider backend for Walker";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.elephant}/bin/elephant";
      Restart = "on-failure";
      RestartSec = "3s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Walker GApplication service — keeps it warm so Super+Space opens instantly
  systemd.user.services.walker = {
    Unit = {
      Description = "Walker launcher GApplication service";
      After = [ "graphical-session.target" "elephant.service" ];
      Wants = [ "elephant.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.walker}/bin/walker --gapplication-service";
      Restart = "on-failure";
      RestartSec = "3s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  xdg.configFile."walker/config.toml".text = ''
    close_when_open = true
    click_to_close = true
    single_click_activation = true
    theme = "dracula"

    [placeholders]
    "default" = { input = "Search", list = "No results" }

    [shell]
    exclusive_zone = -1
    layer = "overlay"
    anchor_top = true
    anchor_bottom = false
    anchor_left = false
    anchor_right = false

    [providers]
    default = ["desktopapplications", "calc", "websearch", "menus", "runner"]
    empty = ["desktopapplications"]
    max_results = 50

    [[providers.prefixes]]
    prefix = "="
    provider = "calc"

    [[providers.prefixes]]
    prefix = "@"
    provider = "websearch"

    [[providers.prefixes]]
    prefix = ">"
    provider = "runner"

    [[providers.prefixes]]
    prefix = "/"
    provider = "files"

    [[providers.prefixes]]
    prefix = ";"
    provider = "providerlist"

    [[providers.prefixes]]
    prefix = ":"
    provider = "clipboard"

    [[providers.prefixes]]
    prefix = "."
    provider = "symbols"
  '';

  # Power actions menu
  xdg.configFile."elephant/menus/power.toml".text = ''
    name = "power"
    name_pretty = "Power"

    [[entries]]
    text = "Shutdown"
    keywords = ["power off", "halt"]
    actions = { run = "systemctl poweroff" }

    [[entries]]
    text = "Reboot"
    keywords = ["restart"]
    actions = { run = "systemctl reboot" }

    [[entries]]
    text = "Suspend"
    keywords = ["sleep"]
    actions = { run = "systemctl suspend-then-hibernate" }

    [[entries]]
    text = "Logout"
    keywords = ["exit", "quit", "hyprland"]
    actions = { run = "hyprctl dispatch exit" }

    [[entries]]
    text = "Lock"
    keywords = ["screen lock"]
    actions = { run = "hyprlock-led" }
  '';

  # Dracula theme — sized as a centered floating panel, not fullscreen
  xdg.configFile."walker/themes/dracula/style.css".text = ''
    * {
      background-color: transparent;
      color: #f8f8f2;
    }

    .box-wrapper {
      background-color: #282a36;
      border-radius: 12px;
      border: 1px solid #44475a;
      box-shadow: 0 8px 32px rgba(0, 0, 0, 0.6);
      min-width: 700px;
      margin-top: 120px;
      padding: 8px;
    }

    .input {
      background-color: #44475a;
      color: #f8f8f2;
      border: none;
      border-radius: 8px;
      padding: 10px 14px;
      caret-color: #bd93f9;
      font-size: 15px;
    }

    .input placeholder {
      color: #6272a4;
    }

    .item-box {
      border-radius: 6px;
      padding: 6px 10px;
    }

    .item-box:selected,
    .item-box:focus {
      background-color: #44475a;
    }

    .item-text-box {
      color: #f8f8f2;
    }

    .item-subtext {
      color: #6272a4;
      font-size: 0.85em;
    }

    .calc {
      color: #50fa7b;
    }

    .placeholder {
      color: #6272a4;
    }
  '';
}
