{ pkgs, ... }:

{
  # ─── Kitty Terminal ───────────────────────────────────────────────────────────
  programs.kitty = {
    enable = true;
    font = {
      name = "JetBrains Mono";
      size = 12;
    };
    settings = {
      shell = "zsh";
      background_opacity = "0.85";
      window_padding_width = 8;
      tab_bar_style = "powerline";
      tab_bar_edge = "top";
      tab_bar_min_tabs = 2;
      copy_on_select = true;
      enable_audio_bell = false;
      confirm_os_window_close = 0;
      placement_strategy = "top-left";
      repaint_delay = 10;
      input_delay = 3;
      sync_to_monitor = true;
      allow_remote_control = "socket-only";
      listen_on = "unix:/tmp/kitty-{kitty_pid}";

      foreground           = "#f8f8f2";
      background           = "#282a36";
      selection_foreground = "#ffffff";
      selection_background = "#44475a";
      cursor               = "#f8f8f2";
      cursor_text_color    = "#282a36";
      url_color            = "#8be9fd";
      url_style            = "curly";
      color0  = "#21222c"; color8  = "#6272a4";
      color1  = "#ff5555"; color9  = "#ff6e6e";
      color2  = "#50fa7b"; color10 = "#69ff94";
      color3  = "#f1fa8c"; color11 = "#ffffa5";
      color4  = "#bd93f9"; color12 = "#d6acff";
      color5  = "#ff79c6"; color13 = "#ff92df";
      color6  = "#8be9fd"; color14 = "#a4ffff";
      color7  = "#f8f8f2"; color15 = "#ffffff";
    };
    shellIntegration.enableBashIntegration = true;
    shellIntegration.enableZshIntegration = true;
  };

  # ─── Fuzzel ────────────────────────────────────────────────────────────────────
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        font = "JetBrainsMono Nerd Font:size=13";
        dpi-aware = "no";
        icon-theme = "Papirus-Dark";
        icons-enabled = true;
        terminal = "kitty";
        layer = "overlay";
        exit-on-keyboard-focus-loss = true;
        width = 35;
        lines = 10;
        horizontal-pad = 16;
        vertical-pad = 12;
        inner-pad = 6;
        border-radius = 10;
      };
      colors = {
        background = "282a36ee";
        text       = "f8f8f2ff";
        match      = "bd93f9ff";
        selection  = "44475aff";
        selection-text = "f8f8f2ff";
        selection-match = "ff79c6ff";
        border     = "bd93f9ff";
      };
      border = {
        width = 2;
        radius = 10;
      };
    };
  };
}
