{ pkgs, lib, user, claude-code, ... }:

let
  computer-use-pkg = pkgs.python3.pkgs.buildPythonApplication {
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
        --prefix PATH : ${pkgs.lib.makeBinPath [
          pkgs.grim
          pkgs.wtype
          pkgs.ydotool
          pkgs.wl-clipboard
          pkgs.hyprland
        ]}
        --set LD_PRELOAD ${pkgs.gtk4-layer-shell}/lib/libgtk4-layer-shell.so
        --set YDOTOOL_SOCKET /run/ydotoold/socket
      )
    '';

    doCheck = false;
  };
in
{
  home.packages = [
    claude-code.packages.${pkgs.stdenv.hostPlatform.system}.default
    computer-use-pkg
  ];

  # ─── Claude Code ────────────────────────────────────────────────────────────

  # MCP servers (registered at user scope in ~/.claude.json via activation script)
  # Can't overwrite ~/.claude.json directly since Claude Code manages other state there.
  # "computer-use" is a reserved name, so we use "hypr-computer-use".
  home.activation.registerMcpServers = let
    claude-cli = claude-code.packages.${pkgs.stdenv.hostPlatform.system}.default;
  in lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # remove stale entry then re-add with current store path
    ${claude-cli}/bin/claude mcp remove --scope user hypr-computer-use 2>/dev/null || true
    ${claude-cli}/bin/claude mcp add --scope user --transport stdio hypr-computer-use -- \
      ${computer-use-pkg}/bin/computer-use-server
  '';

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
  # Written via activation script (not home.file) so Claude Code can modify
  # it at runtime (e.g. /effort). Refreshed on each home-manager switch.
  home.activation.claudeSettings =
    let
      settingsJson = pkgs.writeText "claude-settings.json" (builtins.toJSON {
      model = "claude-opus-4-6";
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
              {
                type = "command";
                command = "~/.claude/hooks/cost-stop.sh";
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
    });
    in
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        install -Dm644 ${settingsJson} "$HOME/.claude/settings.json"
      '';

  # Status line script (Dracula-themed)
  home.file.".claude/statusline.sh" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Claude Code status line — Dracula-themed
      # Layout: session-dur | repo ⎇ branch ~N (age) [worktree] | model ctx% | 5h X% · 7d X% · $X.XX · $X.XX/wk
      set -uo pipefail

      INPUT=$(cat 2>/dev/null) || exit 0

      # Parse JSON fields
      MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "?"')
      COST=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // 0')
      DURATION_MS=$(echo "$INPUT" | jq -r '.cost.total_duration_ms // 0')
      CTX_PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
      RATE_5H=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.used_percentage // 0' | cut -d. -f1)
      RATE_5H_RESET=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.resets_at // empty')
      RATE_7D=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.used_percentage // 0' | cut -d. -f1)
      RATE_7D_RESET=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.resets_at // empty')
      WORKTREE=$(echo "$INPUT" | jq -r '.worktree.name // empty')
      EFFORT=$(echo "$INPUT" | jq -r '.effort.level // empty')

      # Dracula ANSI colors
      PURPLE='\033[38;5;141m'   # bd93f9
      GREEN='\033[38;5;84m'     # 50fa7b
      CYAN='\033[38;5;117m'     # 8be9fd
      ORANGE='\033[38;5;215m'   # ffb86c
      RED='\033[38;5;203m'      # ff5555
      YELLOW='\033[38;5;228m'   # f1fa8c
      FG='\033[38;5;253m'       # f8f8f2
      DIM='\033[38;5;242m'      # 6272a4
      RESET='\033[0m'

      # Session duration from ms
      DURATION_S=$((DURATION_MS / 1000))
      if [ "$DURATION_S" -ge 3600 ]; then
        DUR="$((DURATION_S / 3600))h$((DURATION_S % 3600 / 60))m"
      elif [ "$DURATION_S" -ge 60 ]; then
        DUR="$((DURATION_S / 60))m$((DURATION_S % 60))s"
      else
        DUR="''${DURATION_S}s"
      fi

      # Repo name + git branch + dirty count + last commit age
      REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "")
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

# Rate limit percentage color
      rate_color() {
        local pct="$1"
        if [ "$pct" -ge 80 ]; then
          echo "$RED"
        elif [ "$pct" -ge 50 ]; then
          echo "$ORANGE"
        else
          echo "$GREEN"
        fi
      }

      RATE_5H_COLOR=$(rate_color "$RATE_5H")
      RATE_7D_COLOR=$(rate_color "$RATE_7D")

      # Reset time countdown from unix epoch (omitted if field absent)
      # Always shows two units: Xd Yh or Xh Ym or Xm
      reset_in() {
        local ts="$1"
        [ -z "$ts" ] && return
        local diff=$(( ts - $(date +%s) ))
        [ "$diff" -le 0 ] && return
        if [ "$diff" -ge 86400 ]; then
          echo " $(( diff / 86400 ))d$(( diff % 86400 / 3600 ))h"
        elif [ "$diff" -ge 3600 ]; then
          echo " $(( diff / 3600 ))h$(( diff % 3600 / 60 ))m"
        else
          echo " $(( diff / 60 ))m"
        fi
      }

      RESET_5H=$(reset_in "$RATE_5H_RESET")
      RESET_7D=$(reset_in "$RATE_7D_RESET")

      # Cost formatting (force C locale for decimal point)
      COST_FMT=$(LC_NUMERIC=C printf '%.2f' "$COST")

      # Track session cost so the Stop hook can record it for weekly rollup
      SESSION_CACHE_DIR="$HOME/.cache/claude-sessions"
      mkdir -p "$SESSION_CACHE_DIR"
      printf '%s %s\n' "$(date +%s)" "$COST" > "$SESSION_CACHE_DIR/$PPID"

      # Weekly cost: sum closed sessions from past 7 days (5-min cache) + current session
      WEEKLY_CACHE="$HOME/.cache/claude-weekly-cost"
      COST_LOG_DIR="$HOME/.local/share/claude-costs"
      if [ -n "$RATE_7D_RESET" ]; then
        WEEK_AGO=$(( RATE_7D_RESET - 604800 ))
      else
        WEEK_AGO=$(( $(date +%s) - 604800 ))
      fi
      WEEK_CLOSED=0
      RECOMPUTE=1
      if [ -f "$WEEKLY_CACHE" ]; then
        CACHE_AGE=$(( $(date +%s) - $(stat -c %Y "$WEEKLY_CACHE") ))
        [ "$CACHE_AGE" -lt 300 ] && RECOMPUTE=0
      fi
      if [ "$RECOMPUTE" -eq 1 ]; then
        WEEK_CLOSED=$(
          find "$COST_LOG_DIR" -name "*.log" -maxdepth 1 2>/dev/null | \
          xargs -r awk -v ago="$WEEK_AGO" '
            $1+0 >= ago { sum += $2+0 }
            END { printf "%.6f", sum+0 }
          ' 2>/dev/null || echo 0
        )
        printf '%s\n' "$WEEK_CLOSED" > "$WEEKLY_CACHE"
      else
        WEEK_CLOSED=$(cat "$WEEKLY_CACHE" 2>/dev/null || echo 0)
      fi
      WEEK_COST_FMT=$(LC_NUMERIC=C awk -v c="$COST" -v w="$WEEK_CLOSED" 'BEGIN{printf "%.2f", c+w}')

      # Build status line
      LINE="''${FG}''${DUR}''${RESET}"

      if [ -n "$BRANCH" ]; then
        LINE+=" ''${DIM}|''${RESET} ''${FG}''${REPO}''${RESET} ''${CYAN}⎇ ''${BRANCH}''${RESET}''${DIRTY}''${LAST_COMMIT}"
        if [ -n "$WORKTREE" ]; then
          LINE+=" ''${YELLOW}[''${WORKTREE}]''${RESET}"
        fi
      fi

      EFFORT_TAG=""
      if [ -n "$EFFORT" ]; then
        EFFORT_TAG=" ''${DIM}[''${EFFORT}]''${RESET}"
      fi
      LINE+=" ''${DIM}|''${RESET} ''${PURPLE}''${MODEL}''${RESET}''${EFFORT_TAG} ''${FG}''${CTX_PCT}%''${RESET}"
      LINE+=" ''${DIM}|''${RESET} ''${RATE_5H_COLOR}5h ''${RATE_5H}%''${DIM}''${RESET_5H}''${RESET} ''${DIM}·''${RESET} ''${RATE_7D_COLOR}7d ''${RATE_7D}%''${DIM}''${RESET_7D}''${RESET} ''${DIM}·''${RESET} ''${GREEN}\$''${COST_FMT}''${RESET} ''${DIM}·''${RESET} ''${GREEN}\$''${WEEK_COST_FMT}/wk''${RESET}"

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
      re='rm[[:space:]]+-[[:alpha:]]*r[[:alpha:]]*f[[:alpha:]]*[[:space:]]+/([[:space:];*&|"'\'''`]|$)'
      [[ "$COMMAND" =~ $re ]] && block "Blocked: recursive delete of root filesystem"

      re='rm[[:space:]]+-[[:alpha:]]*r[[:alpha:]]*f[[:alpha:]]*[[:space:]]+(~|\$HOME)/?([[:space:];*&|"'\'''`]|$)'
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

  # Hook: resume media when Claude starts thinking (only if all instances are working)
  home.file.".claude/hooks/youtube-resume.sh" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env bash
      cat >/dev/null 2>&1
      [ -f "$HOME/.claude/youtube-sync" ] || exit 0

      dir="$HOME/.claude/youtube-instances"
      mkdir -p "$dir"

      # record submission time so the pause hook can apply a grace period
      date +%s > "$dir/$PPID.ts"

      # mark this instance as working
      echo working > "$dir/$PPID"

      # clean up stale instances whose process died
      for f in "$dir"/*; do
        [ -f "$f" ] || continue
        pid=$(basename "$f")
        [[ "$pid" == *.ts ]] && continue
        kill -0 "$pid" 2>/dev/null || rm -f "$f" "$dir/$pid.ts"
      done

      # only play if every remaining instance is working
      for f in "$dir"/*; do
        [ -f "$f" ] || continue
        [[ "$(basename "$f")" == *.ts ]] && continue
        if [ "$(cat "$f")" = "idle" ]; then
          exit 0
        fi
      done

      playerctl play 2>/dev/null
      exit 0
    '';
  };

  # Hook: pause media when Claude finishes responding (any idle instance pauses)
  home.file.".claude/hooks/youtube-pause.sh" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env bash
      cat >/dev/null 2>&1
      [ -f "$HOME/.claude/youtube-sync" ] || exit 0

      dir="$HOME/.claude/youtube-instances"
      mkdir -p "$dir"

      # clean up stale instances whose process died
      for f in "$dir"/*; do
        [ -f "$f" ] || continue
        pid=$(basename "$f")
        [[ "$pid" == *.ts ]] && continue
        kill -0 "$pid" 2>/dev/null || rm -f "$f" "$dir/$pid.ts"
      done

      # skip re-pausing within 10s of this session's last prompt submission.
      # without this, fast Claude responses re-pause before the user can submit
      # to other sessions, making multi-session resume impossible.
      ts_file="$dir/$PPID.ts"
      if [ -f "$ts_file" ]; then
        last=$(cat "$ts_file" 2>/dev/null)
        now=$(date +%s)
        if [ -n "$last" ] && [ $((now - last)) -lt 10 ]; then
          exit 0
        fi
      fi

      # mark this instance as idle
      echo idle > "$dir/$PPID"

      playerctl pause 2>/dev/null
      exit 0
    '';
  };

  # Hook: record session cost delta to daily log for weekly rollup.
  # Stop fires after every response, not just at session end, so we log
  # the delta since the last Stop rather than the cumulative cost to avoid
  # inflating the weekly total.
  home.file.".claude/hooks/cost-stop.sh" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -uo pipefail
      cat >/dev/null 2>&1

      SESSION_FILE="$HOME/.cache/claude-sessions/$PPID"
      [ -f "$SESSION_FILE" ] || exit 0

      { read -r TIMESTAMP COST; } < "$SESSION_FILE" 2>/dev/null || exit 0

      COST_LOG_DIR="$HOME/.local/share/claude-costs"
      mkdir -p "$COST_LOG_DIR"

      LOGGED_FILE="$HOME/.cache/claude-sessions/$PPID.logged"
      LAST_LOGGED=$(cat "$LOGGED_FILE" 2>/dev/null || echo 0)

      DELTA=$(LC_NUMERIC=C awk -v c="$COST" -v l="$LAST_LOGGED" 'BEGIN{printf "%.6f", c-l}')

      # Only log if there is meaningful new spend
      if LC_NUMERIC=C awk -v d="$DELTA" 'BEGIN{exit (d > 0.000001) ? 0 : 1}'; then
        printf '%s %s\n' "$TIMESTAMP" "$DELTA" >> "$COST_LOG_DIR/$(date -d @"$TIMESTAMP" +%Y-%m-%d).log"
        printf '%s\n' "$COST" > "$LOGGED_FILE"
      fi

      # Drop logs older than 8 days; clean up stale session tracking files
      find "$COST_LOG_DIR" -name "*.log" -mtime +8 -delete 2>/dev/null || true
      find "$HOME/.cache/claude-sessions" -name "*.logged" -mtime +1 -delete 2>/dev/null || true
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
