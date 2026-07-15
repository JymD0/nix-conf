{ pkgs, lib, ... }:

let
  computer-use-pkg = import ./computer-use.nix { inherit pkgs; };

  # nixpkgs is still on codex 0.130 and GPT 5.6 needs 0.143+, so grab the
  # official static musl build until the nixpkgs package catches up
  codex-bin = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "codex";
    version = "0.144.1";
    src = pkgs.fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${finalAttrs.version}/codex-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-hAka4gxl/MfUEg25fRvVfX/435x2Cft4HHjC671PWig=";
    };
    sourceRoot = ".";
    installPhase = ''
      install -Dm755 codex-x86_64-unknown-linux-musl $out/bin/codex
    '';
  });

  # config.toml content. Written via activation script (like claude settings)
  # so Codex can still tweak it at runtime between rebuilds. The
  # hypr-computer-use MCP server is wired in here since Codex reads MCP
  # servers from config.toml rather than a separate registry.
  configToml = pkgs.writeText "codex-config.toml" ''
    # OpenAI Codex CLI config
    # managed by home-manager (modules/codex.nix)

    approval_policy = "on-request"
    sandbox_mode = "workspace-write"
    model_reasoning_effort = "medium"

    # pin a model here if you want, otherwise Codex tracks its own default
    # tiers: gpt-5.6-sol (heavy) / gpt-5.6-terra (general) / gpt-5.6-luna (light)
    # model = "gpt-5.6-terra"

    [mcp_servers.hypr-computer-use]
    command = "${computer-use-pkg}/bin/computer-use-server"
    args = []
  '';
in
{
  home.packages = [
    codex-bin
    computer-use-pkg
  ];

  # ─── OpenAI Codex ───────────────────────────────────────────────────────────

  home.activation.codexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -Dm644 ${configToml} "$HOME/.codex/config.toml"
  '';

  # Global instructions (Codex reads ~/.codex/AGENTS.md for every session)
  home.file.".codex/AGENTS.md" = {
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
      - Never mention AI in commit messages, PR descriptions, or docs
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
      - Project-specific rule -> add to the project's instructions
      - Specific fact/context -> save to memory

      Choose the narrowest scope that fits.
    '';
  };
}
