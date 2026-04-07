{ pkgs, user, claude-code, ... }:

{
  home.packages = [
    claude-code.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # ─── Claude Code ────────────────────────────────────────────────────────────

  # MCP servers (contains instance URLs — managed here, not in settings.json)
  home.file.".claude/.mcp.json".force = true;
  home.file.".claude/.mcp.json".text = builtins.toJSON {
    mcpServers.metamcp = {
      type = "http";
      url = user.metamcpUrl;
    };
  };

  # Global preferences (applies to every session across all projects)
  home.file.".claude/CLAUDE.md" = {
    force = true;
    text = ''
      # Global Preferences

      ## Environment

      NixOS 24.11, Hyprland, zsh + starship.
      Stack: C, Python, Dart/Flutter, Bash/Zsh, Go, Rust, Kotlin, Java.
      Tooling: ripgrep, fd, fzf, jq, bat, eza, zoxide, tmux.
      Linters: shellcheck, ruff, cppcheck, nixfmt-rfc-style, statix, deadnix, prettier, yamllint.

      ## Workflow

      - If something is unclear or can't be assumed correctly, ask
      - When debugging, show reasoning before the fix
      - Test/build before declaring something done
      - If a task touches 3+ files, outline the plan first
      - Don't refactor or improve code beyond what was asked
      - Never mention Claude or AI in commit messages, PR descriptions, or docs
      - Prefer inline comments over block comments or separate docs

      ## Writing

      - Write docs and comments in a casual, human tone
      - Avoid em dashes, bullet-heavy formatting, and overly structured prose that reads as AI-generated

      ## Principles

      - Declarative over imperative
      - Minimal surface area -- no abstraction unless it solves a real problem
      - Shell scripts start with `set -euo pipefail`

      ## On corrections

      When corrected, extract the general pattern and save it:
      - Universal rule -> add to ~/.claude/rules/corrections.md
      - Project-specific rule -> add to the project's .claude/CLAUDE.md
      - Specific fact/context -> save to memory

      Choose the narrowest scope that fits.
    '';
  };

  # Settings (permissions, hooks, plugins — no secrets)
  home.file.".claude/settings.json" = {
    force = true;
    text = builtins.toJSON {
      env = {
        EDITOR = "vim";
        PAGER = "bat --plain";
      };
      permissions = {
        allow = [
          "WebSearch"
          "WebFetch(domain:github.com)"
          "WebFetch(domain:raw.githubusercontent.com)"
          "WebFetch(domain:gist.github.com)"
          "WebFetch(domain:stackoverflow.com)"
          "WebFetch(domain:developer.mozilla.org)"
          "WebFetch(domain:docs.python.org)"
          "WebFetch(domain:doc.rust-lang.org)"
          "WebFetch(domain:pkg.go.dev)"
          "WebFetch(domain:wiki.hyprland.org)"
          "WebFetch(domain:wiki.hypr.land)"
          "WebFetch(domain:wiki.nixos.org)"
          "WebFetch(domain:search.nixos.org)"
          "WebFetch(domain:nix-community.github.io)"
          "WebFetch(domain:discourse.nixos.org)"
          "WebFetch(domain:www.hyprflux.dev)"
          "Bash(bat:*)"
          "Bash(fd:*)"
          "Bash(eza:*)"
          "Bash(jq:*)"
          "Bash(file:*)"
          "Bash(wc:*)"
          "Bash(du:*)"
          "Bash(df:*)"
          "Bash(which:*)"
          "Bash(type:*)"
          "Bash(tldr:*)"
          "Bash(systemctl status:*)"
          "Bash(systemctl --user status:*)"
          "Bash(systemctl show:*)"
          "Bash(systemctl --user show:*)"
          "Bash(systemctl list-units:*)"
          "Bash(systemctl --user list-units:*)"
          "Bash(systemctl list-timers:*)"
          "Bash(systemctl --user list-timers:*)"
          "Bash(journalctl -n:*)"
          "Bash(journalctl --unit:*)"
          "Bash(journalctl --user-unit:*)"
          "Bash(journalctl -b:*)"
          "Bash(coredumpctl list:*)"
          "Bash(upower:*)"
          "Bash(acpi:*)"
          "Bash(lsblk:*)"
          "Bash(lsusb:*)"
          "Bash(lspci:*)"
          "Bash(ip addr:*)"
          "Bash(ip link:*)"
          "Bash(ip rule:*)"
          "Bash(ip route show:*)"
          "Bash(swapon --show:*)"
          "Bash(free:*)"
          "Bash(uptime:*)"
          "Bash(uname:*)"
          "Bash(hostname:*)"
          "Bash(tailscale status:*)"
          "Bash(ddcutil getvcp:*)"
          "Bash(brightnessctl g:*)"
          "Bash(brightnessctl m:*)"
          "Bash(ps:*)"
          "Bash(pgrep:*)"
          "Bash(fastfetch:*)"
          "Bash(pulsemixer --list-sinks:*)"
          "Bash(playerctl:*)"
          "Bash(hyprctl:*)"
          "Bash(git status:*)"
          "Bash(git log:*)"
          "Bash(git diff:*)"
          "Bash(git branch:*)"
          "Bash(git show:*)"
          "Bash(git remote:*)"
          "Bash(git stash list:*)"
          "Bash(git blame:*)"
          "Bash(git tag:*)"
          "Bash(gh pr view:*)"
          "Bash(gh pr list:*)"
          "Bash(gh pr checks:*)"
          "Bash(gh pr diff:*)"
          "Bash(gh pr status:*)"
          "Bash(gh issue view:*)"
          "Bash(gh issue list:*)"
          "Bash(gh issue status:*)"
          "Bash(gh run view:*)"
          "Bash(gh run list:*)"
          "Bash(gh run watch:*)"
          "Bash(gh repo view:*)"
          "Bash(gh repo list:*)"
          "Bash(gh release view:*)"
          "Bash(gh release list:*)"
          "Bash(gh search:*)"
          "Bash(gh auth status:*)"
          "Bash(gh browse:*)"
          "Bash(nix search:*)"
          "Bash(nix eval:*)"
          "Bash(nix flake show:*)"
          "Bash(nix flake metadata:*)"
          "Bash(nix path-info:*)"
          "Bash(nix-tree:*)"
          "Bash(nix-diff:*)"
          "Bash(nixos-rebuild dry-build:*)"
          "Bash(nix build:*)"
          "Bash(nixfmt:*)"
          "Bash(statix:*)"
          "Bash(deadnix:*)"
          "Bash(prettier:*)"
          "Bash(eslint:*)"
          "Bash(black:*)"
          "Bash(ruff:*)"
          "Bash(rustfmt:*)"
          "Bash(shellcheck:*)"
          "Bash(cargo check:*)"
          "Bash(cargo clippy:*)"
          "Bash(python3 -m py_compile:*)"
          "Bash(cppcheck:*)"
          "Bash(ktlint:*)"
          "Bash(google-java-format:*)"
          "Bash(yamllint:*)"
          "Bash(taplo:*)"
          "Bash(tidy:*)"
          "Bash(stylelint:*)"
          "Read(//proc/**)"
          "Read(//nix/store/**)"
          "Read(//home/${user.username}/.config/**)"
          "Read(//etc/nixos/**)"
          "Read(//etc/hosts)"
          "Read(//etc/resolv.conf)"
          "Read(//etc/os-release)"
        ];
        deny = [
          "Read(//proc/*/environ)"
          "Read(//proc/*/mem)"
          "Read(//proc/*/cmdline)"
          "Read(//proc/kcore)"
          "Read(//proc/kallsyms)"
          "Read(//home/${user.username}/.config/gh/**)"
          "Read(//home/${user.username}/.config/gcloud/**)"
          "Read(//home/${user.username}/.ssh/**)"
          "Read(//home/${user.username}/.gnupg/**)"
          "Read(//home/${user.username}/.aws/**)"
        ];
      };
      hooks = {
        PreToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "~/.claude/hooks/safety.sh";
              }
            ];
          }
        ];
        PostToolUse = [
          {
            matcher = "Edit|Write";
            hooks = [
              {
                type = "command";
                command = "~/.claude/hooks/lint.sh";
                statusMessage = "Linting...";
              }
            ];
          }
        ];
        UserPromptSubmit = [
          {
            hooks = [
              {
                type = "command";
                command = "~/.claude/hooks/youtube-resume.sh";
              }
            ];
          }
        ];
        Stop = [
          {
            hooks = [
              {
                type = "command";
                command = "~/.claude/hooks/youtube-pause.sh";
              }
            ];
          }
        ];
        SessionStart = [
          {
            matcher = "startup";
            hooks = [
              {
                type = "command";
                command = "~/.claude/hooks/startup-context.sh";
              }
            ];
          }
        ];
      };
      statusLine = {
        type = "command";
        command = "~/.claude/statusline.sh";
      };
      enabledPlugins = {
        "superpowers@claude-plugins-official" = true;
        "feature-dev@claude-plugins-official" = true;
      };
      effortLevel = "medium";
    };
  };

  # Status line script (Dracula-themed)
  home.file.".claude/statusline.sh" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Claude Code status line — Dracula-themed
      # Displays: model | git branch (dirty) | context bar | cost | duration | worktree | rate limits
      set -uo pipefail

      INPUT=$(cat 2>/dev/null) || exit 0

      # Parse JSON fields
      MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "?"')
      COST=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // 0')
      DURATION_MS=$(echo "$INPUT" | jq -r '.cost.total_duration_ms // 0')
      CTX_PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
      RATE_5H=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.used_percentage // 0' | cut -d. -f1)
      RATE_7D=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.used_percentage // 0' | cut -d. -f1)
      WORKTREE=$(echo "$INPUT" | jq -r '.worktree.name // empty')

      # Dracula ANSI colors
      PURPLE='\033[38;5;141m'   # bd93f9
      GREEN='\033[38;5;84m'     # 50fa7b
      CYAN='\033[38;5;117m'     # 8be9fd
      ORANGE='\033[38;5;215m'   # ffb86c
      PINK='\033[38;5;212m'     # ff79c6
      RED='\033[38;5;203m'      # ff5555
      YELLOW='\033[38;5;228m'   # f1fa8c
      FG='\033[38;5;253m'       # f8f8f2
      DIM='\033[38;5;242m'      # 6272a4
      RESET='\033[0m'

      # Git branch + dirty file count + last commit age
      BRANCH=$(git branch --show-current 2>/dev/null || echo "")
      DIRTY=""
      LAST_COMMIT=""
      if [ -n "$BRANCH" ]; then
        DIRTY_COUNT=$(git status --porcelain 2>/dev/null | wc -l)
        if [ "$DIRTY_COUNT" -gt 0 ]; then
          DIRTY=" ''${ORANGE}~''${DIRTY_COUNT}''${RESET}"
        fi
        COMMIT_TS=$(git log -1 --format=%ct 2>/dev/null || echo "")
        if [ -n "$COMMIT_TS" ]; then
          AGE_S=$(( $(date +%s) - COMMIT_TS ))
          if [ "$AGE_S" -ge 86400 ]; then
            LAST_COMMIT=" ''${DIM}$(( AGE_S / 86400 ))d ago''${RESET}"
          elif [ "$AGE_S" -ge 3600 ]; then
            LAST_COMMIT=" ''${DIM}$(( AGE_S / 3600 ))h ago''${RESET}"
          else
            LAST_COMMIT=" ''${DIM}$(( AGE_S / 60 ))m ago''${RESET}"
          fi
        fi
      fi

      # Context bar (10 chars wide, using safe block chars)
      FILLED=$((CTX_PCT / 10))
      EMPTY=$((10 - FILLED))
      if [ "$CTX_PCT" -ge 80 ]; then
        BAR_COLOR="$RED"
      elif [ "$CTX_PCT" -ge 50 ]; then
        BAR_COLOR="$ORANGE"
      else
        BAR_COLOR="$GREEN"
      fi
      BAR="''${BAR_COLOR}$(printf '%*s' "$FILLED" "" | tr ' ' '#')''${DIM}$(printf '%*s' "$EMPTY" "" | tr ' ' '-')''${RESET}"

      # Duration: convert ms to human-readable
      DURATION_S=$((DURATION_MS / 1000))
      if [ "$DURATION_S" -ge 3600 ]; then
        DUR="$((DURATION_S / 3600))h$((DURATION_S % 3600 / 60))m"
      elif [ "$DURATION_S" -ge 60 ]; then
        DUR="$((DURATION_S / 60))m$((DURATION_S % 60))s"
      else
        DUR="''${DURATION_S}s"
      fi

      # Cost formatting (force C locale for decimal point)
      COST_FMT=$(LC_NUMERIC=C printf '%.2f' "$COST")

      # Rate limit mini-bars (always visible, 5 chars each)
      rate_bar() {
        local pct="$1" label="$2"
        local fill=$((pct / 20))  # 5 chars wide, each = 20%
        local empty=$((5 - fill))
        local color
        if [ "$pct" -ge 80 ]; then
          color="$RED"
        elif [ "$pct" -ge 50 ]; then
          color="$ORANGE"
        else
          color="$GREEN"
        fi
        echo "''${DIM}''${label}''${RESET}''${color}$(printf '%*s' "$fill" "" | tr ' ' '#')''${DIM}$(printf '%*s' "$empty" "" | tr ' ' '-')''${RESET}"
      }

      RATE_5H_BAR=$(rate_bar "$RATE_5H" "5h")
      RATE_7D_BAR=$(rate_bar "$RATE_7D" "7d")

      # Build status line
      LINE="''${PURPLE}''${MODEL}''${RESET}"

      if [ -n "$BRANCH" ]; then
        LINE+=" ''${DIM}|''${RESET} ''${CYAN}''${BRANCH}''${RESET}''${DIRTY}''${LAST_COMMIT}"
      fi

      if [ -n "$WORKTREE" ]; then
        LINE+=" ''${DIM}|''${RESET} ''${YELLOW}''${WORKTREE}''${RESET}"
      fi

      LINE+=" ''${DIM}|''${RESET} ''${BAR} ''${FG}''${CTX_PCT}%''${RESET}"
      LINE+=" ''${DIM}|''${RESET} ''${GREEN}\$''${COST_FMT}''${RESET}"
      LINE+=" ''${DIM}|''${RESET} ''${PINK}''${DUR}''${RESET}"
      LINE+=" ''${DIM}|''${RESET} ''${RATE_5H_BAR} ''${RATE_7D_BAR}"

      echo -e "$LINE"
    '';
  };

  # Hook: block dangerous bash patterns
  home.file.".claude/hooks/safety.sh" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -uo pipefail

      INPUT=$(cat 2>/dev/null) || exit 0
      TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0

      [ "$TOOL" != "Bash" ] && exit 0

      COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
      [ -z "$COMMAND" ] && exit 0

      block() {
        echo "$1" >&2
        exit 2
      }

      # Filesystem destruction
      re='rm[[:space:]]+-[[:alpha:]]*r[[:alpha:]]*f[[:alpha:]]*[[:space:]]+/([[:space:];*&|"'\''`]|$)'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: recursive delete of root filesystem"

      re='rm[[:space:]]+-[[:alpha:]]*r[[:alpha:]]*f[[:alpha:]]*[[:space:]]+(~|\$HOME)/?([[:space:];*&|"'\''`]|$)'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: recursive delete of home directory"

      re='sudo[[:space:]]+rm[[:space:]]+-[[:alpha:]]*r[[:alpha:]]*f'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: sudo recursive delete — ask the user first"

      # Git destructive operations
      re='git[[:space:]]+push[[:space:]]'
      if [[ "$COMMAND" =~ $re ]]; then
        re_force='(--force([[:space:]]|$)|-f([[:space:]]|$))'
        if [[ "$COMMAND" =~ $re_force ]]; then
          [[ "$COMMAND" =~ --force-with-lease ]] || \
          [[ "$COMMAND" =~ --force-if-includes ]] || \
          block "Blocked: force push — use --force-with-lease or ask the user"
        fi
      fi

      re='git[[:space:]]+reset[[:space:]]+--hard'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: hard reset discards uncommitted work. Ask the user first"

      re='git[[:space:]]+clean[[:space:]]+-[[:alpha:]]*f'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: git clean removes untracked files. Ask the user first"

      re='git[[:space:]]+branch[[:space:]]+-D'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: git branch -D force-deletes a branch. Ask the user first"

      re='git[[:space:]]+checkout[[:space:]]+--[[:space:]]+\.([[:space:]]|$)'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: discarding all working changes. Ask the user first"

      re='git[[:space:]]+restore[[:space:]]+(--[[:alpha:]-]+[[:space:]]+)*\.([[:space:]]|$)'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: discarding all working changes. Ask the user first"

      # Device/disk operations
      re='>[[:space:]]*/dev/'
      if [[ "$COMMAND" =~ $re ]]; then
        re_safe='>[[:space:]]*/dev/(null|stderr|stdout)'
        [[ "$COMMAND" =~ $re_safe ]] || block "Blocked: writing to device files"
      fi

      re='(^|[;&|][[:space:]]*)((sudo[[:space:]]+)?mkfs)'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: filesystem formatting — ask the user first"

      re='(^|[;&|][[:space:]]*)((sudo[[:space:]]+)?dd[[:space:]])'
      if [[ "$COMMAND" =~ $re ]]; then
        [[ "$COMMAND" =~ of=/dev/ ]] && block "Blocked: dd writing to device — ask the user first"
      fi

      # Permissions
      re='chmod[[:space:]]+(-[[:alpha:]]+[[:space:]]+)*777'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: world-writable permissions — use specific permissions instead"

      # Power/system state
      re='(^|[;&|][[:space:]]*)((sudo[[:space:]]+)?(shutdown|poweroff|reboot|halt))([[:space:]]|$)'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: system power operation — ask the user first"

      re='(^|[;&|][[:space:]]*)((sudo[[:space:]]+)?init[[:space:]]+[06])'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: system power operation — ask the user first"

      # Root shell access
      re='(^|[;&|][[:space:]]*)sudo[[:space:]]+(su|bash|sh|-i|-s)([[:space:]]|$)'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: root shell — ask the user first"

      # Journal log manipulation
      re='journalctl.*--vacuum'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: journal log deletion — ask the user first"

      re='journalctl.*--rotate'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: journal log rotation — ask the user first"

      # Hyprland dangerous subcommands
      re='hyprctl[[:space:]]+dispatch[[:space:]]+exec'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: hyprctl dispatch exec runs arbitrary commands — ask the user first"

      re='hyprctl[[:space:]]+kill([[:space:]]|$)'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: hyprctl kill enters interactive window kill mode"

      # Remote code execution
      re='(curl|wget).*\|.*(bash|sh)([[:space:]]|$)'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: piping download to shell — download and inspect the script first"

      # Fork bomb
      [[ "$COMMAND" == *':(){:|:&};:'* ]] && block "Blocked: fork bomb detected"

      exit 0
    '';
  };

  # Hook: lint files after Edit/Write
  home.file.".claude/hooks/lint.sh" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -uo pipefail

      MAX_LINES=20

      INPUT=$(cat 2>/dev/null) || exit 0
      FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
      [ -z "$FILE" ] && exit 0
      [ ! -f "$FILE" ] && exit 0

      EXT="''${FILE##*.}"
      OUTPUT=""
      RAN=false

      run_if_available() {
        local cmd="$1"; shift
        if command -v "$cmd" >/dev/null 2>&1; then
          RAN=true
          OUTPUT+=$("$cmd" "$@" 2>&1 || true)
          OUTPUT+=$'\n'
        fi
      }

      case "$EXT" in
        sh|bash|zsh)
          run_if_available shellcheck "$FILE"
          ;;
        py)
          run_if_available ruff check --no-fix "$FILE"
          ;;
        js|jsx|ts|tsx|mjs|cjs)
          ESLINT_BIN=""
          [ -x "node_modules/.bin/eslint" ] && ESLINT_BIN="node_modules/.bin/eslint"
          if [ -z "$ESLINT_BIN" ] && [ -n "''${CLAUDE_PROJECT_DIR:-}" ]; then
            [ -x "$CLAUDE_PROJECT_DIR/node_modules/.bin/eslint" ] && \
              ESLINT_BIN="$CLAUDE_PROJECT_DIR/node_modules/.bin/eslint"
          fi
          if [ -n "$ESLINT_BIN" ]; then
            RAN=true
            OUTPUT+=$("$ESLINT_BIN" --no-fix "$FILE" 2>&1 || true)
            OUTPUT+=$'\n'
          else
            run_if_available eslint --no-fix "$FILE"
          fi
          ;;
        nix)
          run_if_available statix check "$FILE"
          run_if_available deadnix "$FILE"
          ;;
        json)
          if command -v jq >/dev/null 2>&1; then
            RAN=true
            OUTPUT+=$(jq empty "$FILE" 2>&1 || true)
            OUTPUT+=$'\n'
          fi
          ;;
        yaml|yml)
          run_if_available yamllint -d relaxed "$FILE"
          ;;
        c|h)
          run_if_available cppcheck --quiet --error-exitcode=0 "$FILE"
          ;;
        cpp|cc|cxx|hpp|hh|hxx)
          run_if_available cppcheck --quiet --error-exitcode=0 --language=c++ "$FILE"
          ;;
        java)
          if command -v google-java-format >/dev/null 2>&1; then
            RAN=true
            OUTPUT+=$(google-java-format --dry-run "$FILE" 2>&1 || true)
            OUTPUT+=$'\n'
          fi
          ;;
        kt|kts)
          run_if_available ktlint "$FILE"
          ;;
        html|htm)
          run_if_available tidy -q -e --show-warnings no "$FILE"
          ;;
        css|scss|less)
          run_if_available stylelint "$FILE"
          ;;
        toml)
          run_if_available taplo check "$FILE"
          ;;
        tex|ltx|sty|cls)
          run_if_available chktex -q "$FILE"
          ;;
        md|mdx)
          run_if_available markdownlint-cli2 "$FILE"
          ;;
      esac

      $RAN || exit 0

      OUTPUT=$(echo "$OUTPUT" | sed '/^$/d')

      if [ -z "$OUTPUT" ]; then
        echo "ok"
      else
        TOTAL=$(echo "$OUTPUT" | wc -l)
        if [ "$TOTAL" -le "$MAX_LINES" ]; then
          echo "$OUTPUT"
        else
          echo "$OUTPUT" | head -n "$MAX_LINES"
          echo "... ($((TOTAL - MAX_LINES)) more lines truncated)"
        fi
      fi

      exit 0
    '';
  };

  # Hook: inject git context at session start
  home.file.".claude/hooks/startup-context.sh" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      DIR="''${CLAUDE_PROJECT_DIR:-.}"

      BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null || true)
      [ -n "$BRANCH" ] && echo "Git branch: $BRANCH"

      if git -C "$DIR" diff --quiet 2>/dev/null && git -C "$DIR" diff --cached --quiet 2>/dev/null; then
        true
      else
        echo "Working tree has uncommitted changes"
      fi
    '';
  };

  # Hook: resume media when Claude starts thinking
  home.file.".claude/hooks/youtube-resume.sh" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env bash
      cat >/dev/null 2>&1
      [ -f "$HOME/.claude/youtube-sync" ] && playerctl play 2>/dev/null
      exit 0
    '';
  };

  # Hook: pause media when Claude finishes responding
  home.file.".claude/hooks/youtube-pause.sh" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env bash
      cat >/dev/null 2>&1
      [ -f "$HOME/.claude/youtube-sync" ] && playerctl pause 2>/dev/null
      exit 0
    '';
  };

  # Hook: no-op placeholder for context compaction
  home.file.".claude/hooks/compact-context.sh" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Claude Code already re-injects CLAUDE.md after compaction natively.
      exit 0
    '';
  };
}
