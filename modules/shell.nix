{ config, pkgs, lib, user, ... }:

{
  # ─── Bash ─────────────────────────────────────────────────────────────────────
  programs.bash.enable = true;   # keep as fallback

  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";
    autosuggestion.enable = true;
    syntaxHighlighting = {
      enable = true;
      styles = {
        # Dracula-themed syntax highlighting
        "main"                      = "fg=#f8f8f2";
        "default"                   = "fg=#f8f8f2";
        "unknown-token"             = "fg=#ff5555";
        "reserved-word"             = "fg=#ff79c6,bold";
        "alias"                     = "fg=#50fa7b";
        "builtin"                   = "fg=#8be9fd";
        "function"                  = "fg=#50fa7b";
        "command"                   = "fg=#50fa7b";
        "precommand"                = "fg=#50fa7b,underline";
        "commandseparator"          = "fg=#ff79c6";
        "path"                      = "fg=#f1fa8c";
        "globbing"                  = "fg=#f1fa8c";
        "single-hyphen-option"      = "fg=#ffb86c";
        "double-hyphen-option"      = "fg=#ffb86c";
        "single-quoted-argument"    = "fg=#f1fa8c";
        "double-quoted-argument"    = "fg=#f1fa8c";
        "dollar-quoted-argument"    = "fg=#f1fa8c";
        "back-quoted-argument"      = "fg=#bd93f9";
        "assign"                    = "fg=#f8f8f2";
        "redirection"               = "fg=#ff79c6";
        "comment"                   = "fg=#6272a4";
      };
    };
    historySubstringSearch.enable = true;
    enableCompletion = true;
    history = {
      size = 50000;
      save = 50000;
      ignoreDups = true;
      ignoreAllDups = true;
      ignoreSpace = true;
      extended = true;        # timestamps in history
      share = true;           # share history across sessions
    };
    shellAliases = {
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#$(hostname)";
      update  = "cd /etc/nixos && sudo nix flake update && sudo nixos-rebuild switch --flake .#$(hostname)";
      scpget  = "termscp";
      battery = "upower -i $(upower -e | grep -i bat | head -1)";
      ll      = "eza -la";
      la      = "eza -a";
      lt      = "eza --tree --level=2";
      cat     = "bat";
      ssh     = "kitten ssh";
      gs      = "git status";
      gd      = "git diff";
      gl      = "git log --oneline --graph -20";

      # LED matrix (auto-discovery broken due to libudev-zero in nixpkgs)
      ledmatrix = "inputmodule-control --serial-dev /dev/ttyACM0 led-matrix";

      # Quick helpers
      mkcd    = "(){mkdir -p \"$1\" && cd \"$1\";}";
      ".."    = "cd ..";
      "..."   = "cd ../..";
      "...."  = "cd ../../..";
    };
    initContent = ''
      # ── Completion styling ──────────────────────────────────────────────
      # Case-insensitive, then partial-word, then substring matching
      zstyle ':completion:*' matcher-list \
        'm:{a-zA-Z}={A-Za-z}' \
        'r:|[._-]=* r:|=*' \
        'l:|=* r:|=*'
      # Completion menu with selection
      zstyle ':completion:*' menu select
      # Colored completion list
      zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
      # Group completions by category with headers
      zstyle ':completion:*' group-name '''
      zstyle ':completion:*:descriptions' format '%F{#bd93f9}── %d ──%f'
      zstyle ':completion:*:warnings' format '%F{#ff5555}no matches%f'
      # Show command descriptions in completion
      zstyle ':completion:*' verbose yes
      # Nicer process completion
      zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'

      # ── History substring search keybinds ───────────────────────────────
      bindkey '^[[A' history-substring-search-up
      bindkey '^[[B' history-substring-search-down

      # ── Auto-notify for long-running commands ──────────────────────────
      __cmd_start_time=
      __cmd_name=
      preexec() {
        __cmd_start_time=$EPOCHSECONDS
        __cmd_name="$1"
      }
      precmd() {
        local elapsed=$(( EPOCHSECONDS - ''${__cmd_start_time:-$EPOCHSECONDS} ))
        if (( elapsed >= 10 )) && [[ -n "$__cmd_name" ]]; then
          notify-send -a "Terminal" "Command finished" \
            "\"$__cmd_name\" took ''${elapsed}s"
        fi
        __cmd_start_time=
        __cmd_name=
      }

      # ── Universal extract function ─────────────────────────────────────
      extract() {
        if [[ -f "$1" ]]; then
          case "$1" in
            *.tar.bz2) tar xjf "$1" ;;
            *.tar.gz)  tar xzf "$1" ;;
            *.tar.xz)  tar xJf "$1" ;;
            *.tar.zst) tar --zstd -xf "$1" ;;
            *.bz2)     bunzip2 "$1" ;;
            *.gz)      gunzip "$1" ;;
            *.tar)     tar xf "$1" ;;
            *.tbz2)    tar xjf "$1" ;;
            *.tgz)     tar xzf "$1" ;;
            *.zip)     unzip "$1" ;;
            *.7z)      7z x "$1" ;;
            *.rar)     unrar x "$1" ;;
            *.xz)      unxz "$1" ;;
            *.zst)     unzstd "$1" ;;
            *)         echo "Cannot extract '$1'" ;;
          esac
        else
          echo "'$1' is not a valid file"
        fi
      }
    '';
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = lib.concatStrings [
        "[╭─](dimmed purple)"
        "$os"
        "$directory"
        "$git_branch"
        "$git_status"
        "$git_metrics"
        "$fill"
        "$nix_shell"
        "$python"
        "$nodejs"
        "$rust"
        "$cmd_duration"
        "$line_break"
        "[╰─](dimmed purple)"
        "$character"
      ];
      palette = "dracula";
      palettes.dracula = {
        background = "#282a36";
        foreground = "#f8f8f2";
        purple     = "#bd93f9";
        cyan       = "#8be9fd";
        green      = "#50fa7b";
        red        = "#ff5555";
        yellow     = "#f1fa8c";
        pink       = "#ff79c6";
        orange     = "#ffb86c";
        comment    = "#6272a4";
      };
      os = {
        disabled = false;
        style = "bold purple";
        symbols.NixOS = " ";
      };
      fill.symbol = " ";
      character = {
        success_symbol = "[󰁔](bold purple)";
        error_symbol   = "[󰁔](bold red)";
        vimcmd_symbol  = "[󰁍](bold green)";
      };
      directory = {
        style = "bold cyan";
        read_only = " 󰌾";
        read_only_style = "red";
        truncation_length = 4;
        truncation_symbol = "…/";
        truncate_to_repo = true;
        substitutions = {
          Documents = "󰈙 Documents";
          Downloads = " Downloads";
          Music     = "󰝚 Music";
          Pictures  = " Pictures";
          Projects  = " Projects";
        };
      };
      git_branch = {
        symbol = " ";
        style = "bold purple";
        format = "on [$symbol$branch(:$remote_branch)]($style) ";
        truncation_length = 24;
      };
      git_status = {
        style = "bold pink";
        format = "[$all_status$ahead_behind]($style)";
        conflicted = " ";
        ahead    = "⇡$\{count} ";
        behind   = "⇣$\{count} ";
        diverged = "⇕⇡$\{ahead_count}⇣$\{behind_count} ";
        untracked = "? ";
        stashed  = "📦 ";
        modified = "! ";
        staged   = "+ ";
        renamed  = "» ";
        deleted  = "✘ ";
      };
      git_metrics = {
        disabled = false;
        format = "[+$added]($added_style)/[-$deleted]($deleted_style) ";
        added_style = "bold green";
        deleted_style = "bold red";
      };
      nix_shell = {
        format = "[$symbol$state( \\($name\\))]($style) ";
        symbol = " ";
        style = "bold cyan";
        impure_msg = "[impure](bold orange)";
        pure_msg = "[pure](bold green)";
      };
      python = {
        symbol = "🐍 ";
        style = "bold yellow";
        format = "[$symbol$pyenv_prefix($version )(\\($virtualenv\\) )]($style)";
      };
      nodejs = {
        symbol = " ";
        style = "bold green";
      };
      rust = {
        symbol = "🦀 ";
        style = "bold orange";
      };
      cmd_duration = {
        min_time = 2000;
        style = "bold yellow";
        format = "⏱ [$duration]($style) ";
        show_milliseconds = false;
        show_notifications = false;
      };
    };
  };

  # ─── Eza (ls replacement) ──────────────────────────────────────────────────────
  programs.eza = {
    enable = true;
    icons = "auto";
    git = true;
    extraOptions = [ "--group-directories-first" ];
  };

  # ─── Zoxide (smarter cd) ─────────────────────────────────────────────────────
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # ─── Fzf (fuzzy finder) ─────────────────────────────────────────────────────
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultOptions = [
      "--color=fg:#f8f8f2,bg:#282a36,hl:#bd93f9"
      "--color=fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9"
      "--color=info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6"
      "--color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4"
    ];
    defaultCommand = "fd --type f --hidden --exclude .git";
    fileWidgetCommand = "fd --type f --hidden --exclude .git";
    changeDirWidgetCommand = "fd --type d --hidden --exclude .git";
  };

  # ─── Bat (cat replacement) ──────────────────────────────────────────────────
  programs.bat = {
    enable = true;
    config = {
      theme = "Dracula";
      style = "numbers,changes";
    };
  };

  # ─── Yazi (terminal file manager) ───────────────────────────────────────────
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    shellWrapperName = "y";
  };

  # ─── Git ──────────────────────────────────────────────────────────────────────
  programs.git = {
    enable = true;
    signing.format = "openpgp";
    settings = {
      user = {
        name  = user.fullName;
        email = user.email;
      };
    };
  };

  # ─── SSH ──────────────────────────────────────────────────────────────────────
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks = {
      "*" = {
        addKeysToAgent = "yes"; # auto-add keys to agent on first use
        controlMaster = "auto"; # reuse connections — instant subsequent logins
        controlPath = "~/.ssh/sockets/%r@%h-%p";
        controlPersist = "10m"; # keep idle connections alive 10 min
      };
    } // user.sshHosts;
  };
}
