{ lib, pkgs, ... }:

let
  computer-use-pkg = import ./computer-use.nix { inherit pkgs; };
  remotePiPatcher = ./pi/patch-remote-pi.cjs;
  subagentModel = "openai-codex/gpt-5.6-luna";
  reviewModel = "openai-codex/gpt-5.6-sol";

  pi = pkgs.writeShellScriptBin "pi" ''
    set -euo pipefail
    umask 077
    export NPM_CONFIG_LOGLEVEL=error
    export NPM_CONFIG_FUND=false
    export NPM_CONFIG_AUDIT=false
    export NPM_CONFIG_UPDATE_NOTIFIER=false
    exec "$HOME/.local/share/pi/bin/pi" "$@"
  '';

  huly-mcp = pkgs.writeShellScriptBin "pi-huly-mcp" ''
    set -euo pipefail

    if [[ -z "''${HULY_URL:-}" || -z "''${HULY_WORKSPACE:-}" || -z "''${HULY_TOKEN:-}" ]]; then
      CLAUDE_CONFIG="$HOME/.claude.json"
      if [[ ! -f "$CLAUDE_CONFIG" ]]; then
        echo "Huly credentials are missing. Set HULY_URL, HULY_WORKSPACE, and HULY_TOKEN." >&2
        exit 1
      fi

      export HULY_URL="$(${pkgs.jq}/bin/jq -er '.mcpServers.huly.env.HULY_URL' "$CLAUDE_CONFIG")"
      export HULY_WORKSPACE="$(${pkgs.jq}/bin/jq -er '.mcpServers.huly.env.HULY_WORKSPACE' "$CLAUDE_CONFIG")"
      export HULY_TOKEN="$(${pkgs.jq}/bin/jq -er '.mcpServers.huly.env.HULY_TOKEN' "$CLAUDE_CONFIG")"
    fi

    exec "$HOME/.local/share/pi/bin/huly-mcp" "$@"
  '';

  firecrawl-mcp = pkgs.writeShellScriptBin "pi-firecrawl-mcp" ''
    set -euo pipefail

    if [[ -z "''${FIRECRAWL_API_KEY:-}" && -z "''${FIRECRAWL_OAUTH_TOKEN:-}" ]]; then
      FIRECRAWL_API_KEY="$(${pkgs.libsecret}/bin/secret-tool lookup service pi provider firecrawl 2>/dev/null || true)"
      export FIRECRAWL_API_KEY
    fi

    if [[ -z "''${FIRECRAWL_API_KEY:-}" && -z "''${FIRECRAWL_OAUTH_TOKEN:-}" && -z "''${FIRECRAWL_API_URL:-}" ]]; then
      echo "Firecrawl credentials are missing. Store a key with: secret-tool store --label='Pi Firecrawl' service pi provider firecrawl" >&2
      exit 1
    fi

    exec "$HOME/.local/share/pi/bin/firecrawl-mcp" "$@"
  '';

  playwright-cli = pkgs.writeShellScriptBin "playwright-cli" ''
    set -euo pipefail
    export NO_UPDATE_NOTIFIER=1

    if [[ " $* " == *" open "* ]]; then
      exec "$HOME/.local/share/pi/bin/playwright-cli" \
        --config "$HOME/.pi/agent/playwright.json" "$@"
    fi

    exec "$HOME/.local/share/pi/bin/playwright-cli" "$@"
  '';

  piLintHook = pkgs.writeShellScript "pi-lint-hook" ''
    set -euo pipefail

    INPUT=$(cat)
    echo "$INPUT" | ${pkgs.jq}/bin/jq -r '.files[]? // empty' | while IFS= read -r file; do
      [ -n "$file" ] || continue
      ${pkgs.jq}/bin/jq -nc --arg path "$file" '{tool_args:{path:$path}}' | \
        "$HOME/.claude/hooks/lint.sh"
    done
  '';

  piMediaHook = pkgs.writeShellScript "pi-media-hook" ''
    set -euo pipefail

    cat >/dev/null
    [ -f "$HOME/.claude/youtube-sync" ] || exit 0

    STATE_DIR="$HOME/.pi/youtube-instances"
    STATE_FILE="$STATE_DIR/''${PI_SESSION_ID:-unknown}"
    mkdir -p "$STATE_DIR"

    case "''${1:-}" in
      working)
        echo working > "$STATE_FILE"
        for file in "$STATE_DIR"/*; do
          [ -f "$file" ] || continue
          [ "$(cat "$file")" = idle ] && exit 0
        done
        ${pkgs.playerctl}/bin/playerctl play 2>/dev/null || true
        ;;
      idle)
        echo idle > "$STATE_FILE"
        ${pkgs.playerctl}/bin/playerctl pause 2>/dev/null || true
        ;;
      delete)
        rm -f "$STATE_FILE"
        ;;
    esac
  '';

  settings = {
    defaultProvider = "openai-codex";
    defaultModel = "gpt-5.6-sol";
    defaultThinkingLevel = "high";
    defaultProjectTrust = "ask";
    enabledModels = [
      "openai-codex/gpt-5.6-sol"
      "openai-codex/gpt-5.6-luna"
    ];
    externalEditor = "vim";
    enableInstallTelemetry = false;
    quietStartup = true;
    packages = [
      "npm:@tintinweb/pi-subagents@0.13.0"
      "npm:remote-pi@0.5.4"
      "npm:pi-mcp-adapter@2.11.0"
      "npm:pi-rewind@0.5.0"
      "npm:pi-yaml-hooks@2026.6.14"
      "npm:pi-stack-ops@1.2.0"
      "npm:@narumitw/pi-codex-usage@0.15.1"
    ];
  };

  mcpSettings = {
    settings = {
      toolPrefix = "short";
      idleTimeout = 10;
      outputGuard = true;
    };
    mcpServers = {
      hypr-computer-use = {
        command = "${computer-use-pkg}/bin/computer-use-server";
        lifecycle = "lazy";
      };
      huly = {
        command = "${huly-mcp}/bin/pi-huly-mcp";
        lifecycle = "lazy";
      };
      firecrawl = {
        command = "${firecrawl-mcp}/bin/pi-firecrawl-mcp";
        lifecycle = "lazy";
      };
    };
  };

  hookSettings = {
    hooks = [
      {
        id = "guard-risky-bash";
        event = "tool.before.bash";
        actions = [
          {
            bash.command = "$HOME/.claude/hooks/safety.sh";
            bash.timeout = 15000;
          }
        ];
      }
      {
        id = "lint-changed-files";
        event = "file.changed";
        conditions = [ "matchesCodeFiles" ];
        actions = [
          {
            bash.command = "${piLintHook}";
            bash.timeout = 60000;
          }
        ];
      }
      {
        id = "resume-media-while-working";
        event = "tool.before.*";
        scope = "main";
        actions = [ { bash = "${piMediaHook} working"; } ];
      }
      {
        id = "pause-media-when-idle";
        event = "session.idle";
        scope = "main";
        actions = [ { bash = "${piMediaHook} idle"; } ];
      }
      {
        id = "remove-media-session";
        event = "session.deleted";
        scope = "main";
        actions = [ { bash = "${piMediaHook} delete"; } ];
      }
    ];
  };
in
{
  home.packages = [
    pi
    computer-use-pkg
    huly-mcp
    firecrawl-mcp
    playwright-cli
    pkgs.chromium
  ];

  # Pi installs npm packages into mutable user state. Reapply the pinned
  # remote-pi source fixes after every rebuild so that state follows this module.
  home.activation.patchRemotePi = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="$HOME/.pi/agent/npm/node_modules/remote-pi/dist/index.js"
    if [[ -f "$target" ]]; then
      ${pkgs.nodejs}/bin/node ${remotePiPatcher} "$target"
    fi
  '';

  # Authentication remains runtime state in Pi's auth storage. Everything
  # else is replaced on rebuild so the setup is reproducible.
  home.activation.hardenPiSessions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    sessions="$HOME/.pi/agent/sessions"
    if [[ -d "$sessions" ]]; then
      ${pkgs.findutils}/bin/find "$sessions" -type d -exec chmod 0700 {} +
      ${pkgs.findutils}/bin/find "$sessions" -type f -exec chmod 0600 {} +
    fi
  '';

  home.file.".pi/agent/settings.json" = {
    force = true;
    text = builtins.toJSON settings;
  };

  home.file.".pi/agent/keybindings.json" = {
    force = true;
    text = builtins.toJSON {
      "app.clear" = [ ];
      "app.model.cycleBackward" = "alt+shift+p";
      "app.models.save" = "alt+s";
      "app.session.toggleSort" = "ctrl+shift+s";
      "tui.input.copy" = "ctrl+shift+c";
      "tui.select.cancel" = "escape";
    };
  };

  home.file.".pi/agent/subagents.json" = {
    force = true;
    text = builtins.toJSON {
      defaultJoinMode = "smart";
      defaultMaxTurns = 80;
      fleetView = true;
      graceTurns = 5;
      schedulingEnabled = false;
      scopeModels = true;
      widgetMode = "background";
    };
  };

  home.file.".pi/agent/mcp.json" = {
    force = true;
    text = builtins.toJSON mcpSettings;
  };

  home.file.".pi/agent/playwright.json" = {
    force = true;
    text = builtins.toJSON {
      browser = {
        browserName = "chromium";
        launchOptions.executablePath = "${pkgs.chromium}/bin/chromium";
      };
    };
  };

  home.file.".pi/agent/hook/hooks.yaml" = {
    force = true;
    text = builtins.toJSON hookSettings;
  };

  home.file.".pi/agent/APPEND_SYSTEM.md" = {
    force = true;
    text = ''
      Protect credentials and private data. If a tool exposes a secret, do not reproduce it in responses, logs, commits, or documentation.

      Before broad changes, identify the acceptance criteria and non-goals. Make the smallest change that satisfies them. Before claiming completion, run the relevant checks and inspect the final diff. Report the exact checks run and any remaining limitations.
    '';
  };

  home.file.".pi/agent/AGENTS.md" = {
    force = true;
    text = ''
      # Global Preferences

      ## Environment

      NixOS 24.11, Hyprland, zsh + starship.
      Stack: C, Python, Dart/Flutter, Bash/Zsh, Go, Rust, Kotlin, Java.
      Tooling: ripgrep, fd, fzf, jq, bat, eza, zoxide.
      Linters: shellcheck, ruff, cppcheck, nixfmt-rfc-style, statix, deadnix, prettier, yamllint.

      ## Workflow

      - If something is unclear or can't be assumed correctly, ask
      - When debugging, summarize the diagnosis and supporting evidence before the fix
      - Test/build before declaring something done
      - If a task touches 3+ files, outline the plan first
      - Don't refactor or improve code beyond what was asked
      - Never mention AI in commit messages, PR descriptions, or docs
      - Prefer inline comments over block comments or separate docs

      ## Writing

      - Write docs and comments in a casual, human tone
      - Avoid em dashes, bullet-heavy formatting, and overly structured prose that reads as AI-generated

      ## Principles

      - Declarative over imperative
      - Minimal surface area -- no abstraction unless it solves a real problem
      - Shell scripts start with `set -euo pipefail`
    '';
  };

  home.file.".pi/agent/agents/general-purpose.md" = {
    force = true;
    text = ''
      ---
      description: "General-purpose agent for researching complex questions, searching for code, and executing multi-step tasks. When you are searching for a keyword or file and are not confident that you will find the right match in the first few tries use this agent to perform the search for you."
      display_name: Agent
      tools: all
      disallowed_tools: project_tasks
      model: ${subagentModel}
      max_turns: 80
      exclude_extensions: process-manager, desktop-notifications
      prompt_mode: append
      ---
    '';
  };

  home.file.".pi/agent/agents/Explore.md" = {
    force = true;
    text = ''
      ---
      description: "Fast read-only search agent for locating code. Use it to find files by pattern (eg. \"src/components/**/*.tsx\"), grep for symbols or keywords (eg. \"API endpoints\"), or answer \"where is X defined / which files reference Y.\" Do NOT use it for code review, design-doc auditing, cross-file consistency checks, or open-ended analysis — it reads excerpts rather than whole files and will miss content past its read window. When calling, specify search breadth: \"quick\" for a single targeted lookup, \"medium\" for moderate exploration, or \"very thorough\" to search across multiple locations and naming conventions."
      display_name: Explore
      tools: read, grep, find, ls, ext:git-inspect/git_inspect
      disallowed_tools: project_tasks
      model: ${subagentModel}
      thinking: medium
      max_turns: 30
      extensions: [pi-yaml-hooks, git-inspect]
      skills: false
      prompt_mode: replace
      ---

      # CRITICAL: READ-ONLY MODE - NO FILE MODIFICATIONS
      You are a file search specialist. You excel at thoroughly navigating and exploring codebases.
      Your role is EXCLUSIVELY to search and analyze existing code. You do NOT have access to file editing tools.

      You are STRICTLY PROHIBITED from:
      - Creating new files
      - Modifying existing files
      - Deleting files
      - Moving or copying files
      - Creating temporary files anywhere, including /tmp
      - Using redirect operators (>, >>, |) or heredocs to write to files
      - Running ANY commands that change system state

      # Tool Usage
      - Use the find tool for file pattern matching
      - Use the grep tool for content search
      - Use the read tool for reading files
      - Use git_inspect for Git status, diffs, and history
      - Make independent tool calls in parallel for efficiency
      - Adapt search approach based on thoroughness level specified

      # Output
      - Use absolute file paths in all references
      - Report findings as regular messages
      - Do not use emojis
      - Be thorough and precise
    '';
  };

  home.file.".pi/agent/agents/Plan.md" = {
    force = true;
    text = ''
      ---
      description: "Software architect agent for designing implementation plans. Use this when you need to plan the implementation strategy for a task. Returns step-by-step plans, identifies critical files, and considers architectural trade-offs."
      display_name: Plan
      tools: read, grep, find, ls, ext:git-inspect/git_inspect
      disallowed_tools: project_tasks
      model: ${subagentModel}
      thinking: high
      max_turns: 40
      extensions: [pi-yaml-hooks, git-inspect]
      skills: false
      prompt_mode: replace
      ---

      # CRITICAL: READ-ONLY MODE - NO FILE MODIFICATIONS
      You are a software architect and planning specialist.
      Your role is EXCLUSIVELY to explore the codebase and design implementation plans.
      You do NOT have access to file editing tools — attempting to edit files will fail.

      You are STRICTLY PROHIBITED from:
      - Creating new files
      - Modifying existing files
      - Deleting files
      - Moving or copying files
      - Creating temporary files anywhere, including /tmp
      - Using redirect operators (>, >>, |) or heredocs to write to files
      - Running ANY commands that change system state

      # Planning Process
      1. Understand requirements
      2. Explore thoroughly (read files, find patterns, understand architecture)
      3. Design solution based on your assigned perspective
      4. Detail the plan with step-by-step implementation strategy

      # Requirements
      - Consider trade-offs and architectural decisions
      - Identify dependencies and sequencing
      - Anticipate potential challenges
      - Follow existing patterns where appropriate

      # Tool Usage
      - Use the find tool for file pattern matching
      - Use the grep tool for content search
      - Use the read tool for reading files
      - Use git_inspect for Git status, diffs, and history

      # Output Format
      - Use absolute file paths
      - Do not use emojis
      - End your response with:

      ### Critical Files for Implementation
      List 3-5 files most critical for implementing the plan:
      - /absolute/path/to/file.ts - [Brief reason]
    '';
  };

  home.file.".pi/agent/agents/Implement.md" = {
    force = true;
    text = ''
      ---
      description: "Implementation agent for substantial, well-scoped coding tasks. Runs in an isolated git worktree, makes minimal changes, executes relevant checks, and returns the resulting branch. Use only when the committed repository state contains all required inputs."
      display_name: Implement
      tools: read, bash, edit, write, grep, find, ls, ext:git-inspect/git_inspect, ext:project-check/project_check
      model: ${reviewModel}
      thinking: high
      max_turns: 80
      extensions: [pi-yaml-hooks, git-inspect, project-check]
      skills: false
      isolation: worktree
      prompt_mode: append
      ---

      Implement the assigned task in the isolated worktree. Respect the stated scope and non-goals. Inspect existing patterns before editing, avoid unrelated refactors, run the closest relevant tests, and inspect the final diff. Report the branch, files changed, checks run, and remaining risks. Do not claim completion when required checks have not passed.
    '';
  };

  home.file.".pi/agent/agents/Review.md" = {
    force = true;
    text = ''
      ---
      description: "Fresh-context code reviewer for completed changes. Use after nontrivial implementation to find correctness, security, regression, and test-coverage issues. Read-only and evidence-driven."
      display_name: Review
      tools: read, grep, find, ls, ext:git-inspect/git_inspect
      model: ${reviewModel}
      thinking: high
      max_turns: 40
      extensions: [pi-yaml-hooks, git-inspect]
      skills: false
      prompt_mode: append
      ---

      Review the requested change without modifying files. Start from the acceptance criteria, inspect the actual diff with git_inspect, and read the relevant surrounding code. Prioritize concrete correctness, security, regression, and missing-test findings. Cite file paths and lines. Do not invent issues to fill a report; say clearly when no actionable issue is found.
    '';
  };

  home.file.".pi/agent/agents/Verify.md" = {
    force = true;
    text = ''
      ---
      description: "Verification agent that checks acceptance criteria and runs focused tests, linters, builds, and final diff inspection without editing source files."
      display_name: Verify
      tools: read, grep, find, ls, ext:git-inspect/git_inspect, ext:project-check/project_check
      model: ${subagentModel}
      thinking: medium
      max_turns: 40
      extensions: [pi-yaml-hooks, git-inspect, project-check]
      skills: false
      prompt_mode: append
      ---

      Verify the assigned change without editing source files. Translate the acceptance criteria into focused project_check actions and inspect the final diff with git_inspect. Build artifacts created by verification are allowed. Report each command and result, distinguish failures caused by the change from environment failures, and identify anything that remains unverified.
    '';
  };

  home.file.".pi/agent/prompts/commit.md" = {
    force = true;
    source = ./pi/prompts/commit.md;
  };
  home.file.".pi/agent/prompts/fix.md" = {
    force = true;
    source = ./pi/prompts/fix.md;
  };
  home.file.".pi/agent/prompts/plan-task.md" = {
    force = true;
    source = ./pi/prompts/plan-task.md;
  };
  home.file.".pi/agent/prompts/solve.md" = {
    force = true;
    source = ./pi/prompts/solve.md;
  };
  home.file.".pi/agent/prompts/spec.md" = {
    force = true;
    source = ./pi/prompts/spec.md;
  };
  home.file.".pi/agent/prompts/review.md" = {
    force = true;
    source = ./pi/prompts/review.md;
  };
  home.file.".pi/agent/prompts/team.md" = {
    force = true;
    source = ./pi/prompts/team.md;
  };
  home.file.".pi/agent/prompts/test.md" = {
    force = true;
    source = ./pi/prompts/test.md;
  };
  home.file.".pi/agent/prompts/wrap-up.md" = {
    force = true;
    source = ./pi/prompts/wrap-up.md;
  };

  home.file.".pi/agent/skills/playwright-browser/SKILL.md" = {
    force = true;
    text = ''
      ---
      name: playwright-browser
      description: Automate and inspect websites with Playwright CLI. Use for browser navigation, authenticated sessions, clicking, forms, accessibility snapshots, screenshots, network inspection, browser testing, and reproducing frontend issues.
      ---

      # Playwright Browser

      Use `playwright-cli` for structured browser interaction. Run `playwright-cli --help` before using unfamiliar commands.

      ## Workflow

      1. Open the target with `playwright-cli -s=pi open <url>`.
      2. Inspect it with `playwright-cli -s=pi snapshot --depth=4`.
      3. Interact using element refs from the latest snapshot.
      4. Take another focused snapshot after navigation or significant page changes.
      5. Use `console`, `requests`, screenshots, or tracing only when the task needs them.
      6. Close the session with `playwright-cli -s=pi close` when finished.

      Prefer Firecrawl for ordinary search and page reading. Use Playwright when the page requires interaction, authentication, JavaScript state, or browser-level debugging. Never submit purchases, publish content, or perform other consequential actions without explicit user approval.
    '';
  };

  home.file.".pi/agent/extensions/ask-question.ts" = {
    force = true;
    source = ./pi/extensions/ask-question.ts;
  };
  home.file.".pi/agent/extensions/claude-controls.ts" = {
    force = true;
    source = ./pi/extensions/claude-controls.ts;
  };
  home.file.".pi/agent/extensions/git-inspect.ts" = {
    force = true;
    source = ./pi/extensions/git-inspect.ts;
  };
  home.file.".pi/agent/extensions/desktop-notifications.ts" = {
    force = true;
    source = ./pi/extensions/desktop-notifications.ts;
  };
  home.file.".pi/agent/extensions/plan-mode.ts" = {
    force = true;
    source = ./pi/extensions/plan-mode.ts;
  };
  home.file.".pi/agent/extensions/process-manager.ts" = {
    force = true;
    source = ./pi/extensions/process-manager.ts;
  };
  home.file.".pi/agent/extensions/project-check.ts" = {
    force = true;
    source = ./pi/extensions/project-check.ts;
  };
  home.file.".pi/agent/extensions/project-tasks.ts" = {
    force = true;
    source = ./pi/extensions/project-tasks.ts;
  };

  home.file.".pi/agent/lib/bounded-exec.ts" = {
    force = true;
    source = ./pi/lib/bounded-exec.ts;
  };
  home.file.".pi/agent/lib/git-inspect-core.ts" = {
    force = true;
    source = ./pi/lib/git-inspect-core.ts;
  };
  home.file.".pi/agent/lib/project-check-core.ts" = {
    force = true;
    source = ./pi/lib/project-check-core.ts;
  };

  home.file.".pi/agent/extensions/prompt-stash.ts" = {
    force = true;
    text = ''
      import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

      const STATUS_KEY = "prompt-stash";

      export default function (pi: ExtensionAPI) {
        const stashed: string[] = [];

        const updateStatus = (ctx: ExtensionContext) => {
          if (!ctx.hasUI) return;
          ctx.ui.setStatus(STATUS_KEY, stashed.length > 0 ? `󰆓 ''${stashed.length}` : undefined);
        };

        pi.on("session_start", async (_event, ctx) => {
          stashed.length = 0;
          updateStatus(ctx);
        });

        pi.registerShortcut("ctrl+s", {
          description: "Stash or restore the editor prompt",
          handler: async (ctx) => {
            const current = ctx.ui.getEditorText();
            if (current.trim()) {
              stashed.push(current);
              ctx.ui.setEditorText("");
              updateStatus(ctx);
              ctx.ui.notify(`Prompt stashed (''${stashed.length})`, "info");
              return;
            }

            const restored = stashed.pop();
            if (restored == null) {
              ctx.ui.notify("No stashed prompt", "info");
              return;
            }

            ctx.ui.setEditorText(restored);
            updateStatus(ctx);
            ctx.ui.notify("Prompt restored", "info");
          },
        });

        pi.on("input", (event, ctx) => {
          if (event.source !== "interactive" || stashed.length === 0) return;

          const restored = stashed.pop();
          if (restored == null) return;
          ctx.ui.setEditorText(restored);
          updateStatus(ctx);
          ctx.ui.notify("Stashed prompt restored", "info");
        });
      }
    '';
  };

  home.file.".pi/agent/extensions/statusline.ts" = {
    force = true;
    text = ''
      import type { AssistantMessage } from "@earendil-works/pi-ai";
      import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
      import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
      import { execFileSync } from "node:child_process";
      import { basename } from "node:path";

      function git(ctx: ExtensionContext, args: string[]): string {
        try {
          return execFileSync("git", args, {
            cwd: ctx.cwd,
            encoding: "utf8",
            stdio: ["ignore", "pipe", "ignore"],
            timeout: 200,
          }).trim();
        } catch {
          return "";
        }
      }

      function setStatusline(pi: ExtensionAPI, ctx: ExtensionContext, startedAt: number) {
        if (ctx.mode !== "tui") return;
        ctx.ui.setHeader((_tui, theme) => ({
          invalidate() {},
          render(width: number): string[] {
            const model = ctx.model?.id || "no model";
            const title = theme.fg("accent", theme.bold("π  Pi"));
            const subtitle = theme.fg("muted", `''${model} · ''${pi.getThinkingLevel()} reasoning`);
            const help = theme.fg("dim", "/help · /model · /plan-mode read-only · Ctrl+S stash");
            return [title, subtitle, help].map((line) => truncateToWidth(line, width));
          },
        }));

        ctx.ui.setFooter((tui, theme, footerData) => {
          const unsubscribe = footerData.onBranchChange(() => tui.requestRender());

          return {
            dispose: unsubscribe,
            invalidate() {},
            render(width: number): string[] {
              let input = 0;
              let output = 0;
              let cost = 0;

              for (const entry of ctx.sessionManager.getBranch()) {
                if (entry.type === "message" && entry.message.role === "assistant") {
                  const message = entry.message as AssistantMessage;
                  input += message.usage.input;
                  output += message.usage.output;
                  cost += message.usage.cost.total;
                }
              }

              const compact = (value: number) =>
                value < 1000 ? String(value) : `''${(value / 1000).toFixed(1)}k`;
              const branch = footerData.getGitBranch();
              const directory = ctx.cwd.split("/").pop() || ctx.cwd;
              const dirty = git(ctx, ["status", "--porcelain"]);
              const gitDir = git(ctx, ["rev-parse", "--git-dir"]);
              const worktree = gitDir.includes("/worktrees/") ? basename(ctx.cwd) : "";
              const elapsed = Math.max(0, Math.floor((Date.now() - startedAt) / 1000));
              const duration = `''${Math.floor(elapsed / 60)}m''${String(elapsed % 60).padStart(2, "0")}s`;
              const context = ctx.getContextUsage();
              const contextValue = context?.tokens == null
                ? null
                : Math.round((context.tokens / context.contextWindow) * 100);
              const contextColor: "muted" | "success" | "warning" | "error" = contextValue == null
                ? "muted"
                : contextValue >= 90 ? "error" : contextValue >= 70 ? "warning" : "success";
              const thinking = pi.getThinkingLevel();
              const thinkingColors = {
                off: "thinkingOff",
                minimal: "thinkingMinimal",
                low: "thinkingLow",
                medium: "thinkingMedium",
                high: "thinkingHigh",
                xhigh: "thinkingXhigh",
                max: "thinkingMax",
              } as const;
              const separator = theme.fg("dim", " │ ");
              const statuses = footerData.getExtensionStatuses();
              const usage = statuses.get("codex-usage");
              const promptStash = statuses.get("prompt-stash");
              const planMode = statuses.get("plan-mode");
              const projectTasks = statuses.get("project-tasks");
              const backgroundProcesses = statuses.get("background-processes");
              const styleQuota = (value: string): string => {
                if (/error|unavailable/i.test(value)) {
                  return theme.fg("warning", `󰓅 ''${value}`);
                }

                const windows = new Map<string, RegExpMatchArray>();
                for (const match of value.matchAll(/\b(5h|wk)\s+(\d+)%(?:→(\S+))?/g)) {
                  if (match[1]) windows.set(match[1], match);
                }
                if (windows.size === 0) return theme.fg("muted", `󰓅 ''${value}`);

                const renderWindow = (label: "5h" | "wk"): string => {
                  const match = windows.get(label);
                  if (!match?.[2]) return theme.fg("dim", `''${label} n/a`);
                  const remaining = Number(match[2]);
                  const color: "success" | "warning" | "error" = remaining <= 20
                    ? "error"
                    : remaining <= 50 ? "warning" : "success";
                  return theme.fg("accent", label)
                    + " " + theme.fg(color, `''${remaining}%`)
                    + (match[3] ? theme.fg("dim", `→''${match[3]}`) : "");
                };

                return theme.fg("muted", `󰓅 ''${value.split(/\s+/)[0]}`)
                  + " " + [renderWindow("5h"), renderWindow("wk")].join(theme.fg("dim", " · "));
              };
              const repo = git(ctx, ["rev-parse", "--show-toplevel"]);
              const repoName = repo ? basename(repo) : directory;
              const gitStatus = branch
                ? theme.fg("accent", ` ''${branch}`)
                  + (dirty ? theme.fg("warning", " ●") : theme.fg("success", " ✓"))
                : theme.fg("muted", "󰊢 no git");
              const left = [
                theme.fg("dim", `󱎫 ''${duration}`),
                theme.fg("text", `󰉋 ''${repoName}`),
                gitStatus,
                ...(worktree ? [theme.fg("warning", `󰘬 ''${worktree}`)] : []),
              ].join(separator);
              const contextStatus = theme.fg(
                contextColor,
                `󰍛 ''${contextValue == null ? "?" : contextValue}%`,
              );
              const rightParts = width < 100
                ? [
                    contextStatus,
                    ...(usage ? [styleQuota(usage)] : []),
                    ...(planMode ? [theme.fg("warning", planMode)] : []),
                    ...(promptStash ? [theme.fg("muted", promptStash)] : []),
                  ]
                : [
                    theme.fg("accent", `󰧑 ''${ctx.model?.id || "no model"}`),
                    theme.fg(thinkingColors[thinking], `󰔛 ''${thinking}`),
                    contextStatus,
                    ...(planMode ? [theme.fg("warning", planMode)] : []),
                    ...(promptStash ? [theme.fg("muted", promptStash)] : []),
                    ...(width >= 140 && projectTasks ? [theme.fg("muted", projectTasks)] : []),
                    ...(width >= 140 && backgroundProcesses ? [theme.fg("muted", backgroundProcesses)] : []),
                    ...(usage ? [styleQuota(usage)] : []),
                  ];
              if (width >= 150) {
                rightParts.push(theme.fg("dim", `↑''${compact(input)} ↓''${compact(output)} $''${cost.toFixed(3)}`));
              }
              const right = rightParts.join(separator);
              const availableLeft = Math.max(0, width - visibleWidth(right) - 1);
              const fittedLeft = truncateToWidth(left, availableLeft);
              const padding = " ".repeat(Math.max(1, width - visibleWidth(fittedLeft) - visibleWidth(right)));

              return [truncateToWidth(fittedLeft + padding + right, width)];
            },
          };
        });
      }

      export default function (pi: ExtensionAPI) {
        const startedAt = Date.now();
        pi.registerCommand("clear", {
          description: "Start a new session",
          handler: async (_args, ctx) => {
            await ctx.waitForIdle();
            await ctx.newSession({ withSession: async () => {} });
          },
        });
        pi.on("session_start", async (_event, ctx) => setStatusline(pi, ctx, startedAt));
      }
    '';
  };
}
