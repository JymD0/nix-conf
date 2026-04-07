{ pkgs, ... }:

let
  # ─── AI backend wrapper ───────────────────────────────────────────────────────
  # Central script that all AI feature scripts call.
  # Config: ~/.config/ai/config (URLs + models only, NO keys)
  # Keys: stored in GNOME Keyring via secret-tool
  # Usage:
  #   ai "what is NixOS"
  #   echo "text" | ai "summarize this"
  #   ai --provider openrouter "hello"
  #   ai --provider litellm --model claude-sonnet "hello"
  aiScript = pkgs.writeShellScriptBin "ai" ''
    set -euo pipefail

    CONFIG="$HOME/.config/ai/config"
    if [ ! -f "$CONFIG" ]; then
      echo "Error: Missing $CONFIG" >&2
      echo "" >&2
      echo "Create it with:" >&2
      echo "  mkdir -p ~/.config/ai" >&2
      echo '  cat > ~/.config/ai/config << EOF' >&2
      echo 'DEFAULT_PROVIDER=litellm' >&2
      echo ''' >&2
      echo 'LITELLM_URL=http://localhost:4000/v1' >&2
      echo 'LITELLM_MODEL=claude-sonnet' >&2
      echo ''' >&2
      echo 'OPENROUTER_URL=https://openrouter.ai/api/v1' >&2
      echo 'OPENROUTER_MODEL=anthropic/claude-sonnet' >&2
      echo 'EOF' >&2
      echo "" >&2
      echo "Then store your API keys:" >&2
      echo "  secret-tool store --label='''LiteLLM API Key''' service ai-backend provider litellm" >&2
      echo "  secret-tool store --label='''OpenRouter API Key''' service ai-backend provider openrouter" >&2
      exit 1
    fi

    source "$CONFIG"

    PROVIDER="''${DEFAULT_PROVIDER:-litellm}"
    MODEL=""
    SYSTEM_PROMPT=""
    PROMPT=""
    MAX_TOKENS="2048"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --provider) PROVIDER="$2"; shift 2 ;;
        --model)    MODEL="$2"; shift 2 ;;
        --system)   SYSTEM_PROMPT="$2"; shift 2 ;;
        --max-tokens) MAX_TOKENS="$2"; shift 2 ;;
        --raw)      RAW=1; shift ;;
        --ask)      ASK=1; shift ;;
        *)          PROMPT="$1"; shift ;;
      esac
    done

    # Interactive mode: prompt via fuzzel (for keybind use)
    if [ "''${ASK:-}" = "1" ] && [ -z "$PROMPT" ]; then
      PROMPT=$(echo "" | ${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt "  AI: " --width 50 --lines 0) || exit 0
      [ -z "$PROMPT" ] && exit 0
    fi

    # Retrieve API key from GNOME Keyring
    API_KEY=$(${pkgs.libsecret}/bin/secret-tool lookup service ai-backend provider "$PROVIDER" 2>/dev/null || true)
    if [ -z "$API_KEY" ]; then
      echo "Error: No API key found in keyring for provider '$PROVIDER'" >&2
      echo "Store it with:" >&2
      echo "  secret-tool store --label='$PROVIDER API Key' service ai-backend provider $PROVIDER" >&2
      exit 1
    fi

    case "$PROVIDER" in
      litellm)
        API_URL="''${LITELLM_URL:-http://localhost:4000/v1}"
        [ -z "$MODEL" ] && MODEL="''${LITELLM_MODEL:-claude-sonnet}"
        ;;
      openrouter)
        API_URL="''${OPENROUTER_URL:-https://openrouter.ai/api/v1}"
        [ -z "$MODEL" ] && MODEL="''${OPENROUTER_MODEL:-anthropic/claude-sonnet}"
        ;;
      *)
        echo "Error: Unknown provider '$PROVIDER'. Use 'litellm' or 'openrouter'." >&2
        exit 1
        ;;
    esac

    STDIN_CONTENT=""
    if [ ! -t 0 ]; then
      STDIN_CONTENT=$(cat)
    fi

    if [ -z "$PROMPT" ] && [ -z "$STDIN_CONTENT" ]; then
      echo "Usage: ai [--provider litellm|openrouter] [--model name] [--system prompt] \"prompt\"" >&2
      echo "       echo \"text\" | ai \"prompt\"" >&2
      exit 1
    fi

    USER_CONTENT=""
    if [ -n "$STDIN_CONTENT" ] && [ -n "$PROMPT" ]; then
      USER_CONTENT="$PROMPT\n\n$STDIN_CONTENT"
    elif [ -n "$STDIN_CONTENT" ]; then
      USER_CONTENT="$STDIN_CONTENT"
    else
      USER_CONTENT="$PROMPT"
    fi

    MESSAGES=""
    if [ -n "$SYSTEM_PROMPT" ]; then
      MESSAGES=$(${pkgs.jq}/bin/jq -nc \
        --arg sys "$SYSTEM_PROMPT" \
        --arg usr "$USER_CONTENT" \
        '[{"role":"system","content":$sys},{"role":"user","content":$usr}]')
    else
      MESSAGES=$(${pkgs.jq}/bin/jq -nc \
        --arg usr "$USER_CONTENT" \
        '[{"role":"user","content":$usr}]')
    fi

    BODY=$(${pkgs.jq}/bin/jq -nc \
      --arg model "$MODEL" \
      --argjson msgs "$MESSAGES" \
      --argjson max "$MAX_TOKENS" \
      '{"model":$model,"messages":$msgs,"max_tokens":$max}')

    RESPONSE=$(${pkgs.curl}/bin/curl -s \
      "''${API_URL}/chat/completions" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      -d "$BODY")

    ERROR=$(echo "$RESPONSE" | ${pkgs.jq}/bin/jq -r '.error.message // empty' 2>/dev/null)
    if [ -n "$ERROR" ]; then
      echo "API Error: $ERROR" >&2
      exit 1
    fi

    if [ "''${RAW:-}" = "1" ]; then
      echo "$RESPONSE"
    else
      echo "$RESPONSE" | ${pkgs.jq}/bin/jq -r '.choices[0].message.content // "No response"'
    fi
  '';

in
{
  home.packages = [ aiScript ];
}
