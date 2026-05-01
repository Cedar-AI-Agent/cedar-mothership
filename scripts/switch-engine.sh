#!/bin/bash
#
# Cedar Switch-Engine Script
# --------------------------
# Flips the ngrok tunnel between port 8080 (cedar-engine) and port 9000
# (cedar-service). Useful when you started with one and need the other
# without re-running cedar-start.
#
# Usage:
#   ./switch-engine.sh        # toggle (8080 <-> 9000)
#   ./switch-engine.sh 8080   # force engine
#   ./switch-engine.sh 9000   # force service
#   ./switch-engine.sh --help

set -e

# Script lives in cedar-mothership/scripts/. CEDAR_ROOT is two dirs up.
CEDAR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ---------- args ----------
case "${1:-}" in
  -h|--help)
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

EXPLICIT_TARGET="${1:-}"
if [ -n "$EXPLICIT_TARGET" ] && [ "$EXPLICIT_TARGET" != "8080" ] && [ "$EXPLICIT_TARGET" != "9000" ]; then
  echo "Error: target port must be 8080 or 9000 (got: $EXPLICIT_TARGET)" >&2
  exit 1
fi

# ---------- detect current ngrok port ----------
CURRENT_PORT=""
NGROK_PID=$(pgrep -x ngrok | head -n1)
if [ -n "$NGROK_PID" ]; then
  NGROK_CMD=$(ps -p "$NGROK_PID" -o args= 2>/dev/null)
  # ngrok command line ends with the port number (e.g. `ngrok http --url=... 8080`)
  CURRENT_PORT=$(echo "$NGROK_CMD" | grep -oE '[0-9]{2,5}[[:space:]]*$' | tr -d ' ')
fi

# ---------- pick target ----------
if [ -n "$EXPLICIT_TARGET" ]; then
  TARGET_PORT="$EXPLICIT_TARGET"
else
  case "$CURRENT_PORT" in
    8080) TARGET_PORT=9000 ;;
    9000) TARGET_PORT=8080 ;;
    *)    TARGET_PORT=8080 ;;  # default to engine if nothing was running
  esac
fi

# Map port -> human label.
case "$TARGET_PORT" in
  8080) TARGET_LABEL="cedar-engine" ;;
  9000) TARGET_LABEL="cedar-service" ;;
esac

# ---------- domain ----------
# Same resolution chain as start.sh: env var first, then cedar-service/.env.
NGROK_DOMAIN="${CEDAR_NGROK_DOMAIN:-}"
ENV_FILE="$CEDAR_ROOT/cedar-service/.env"
if [ -z "$NGROK_DOMAIN" ] && [ -f "$ENV_FILE" ]; then
  ENV_URL=$(grep -E "^CEDAR_ENGINE_URL=" "$ENV_FILE" | tail -n1 | cut -d'=' -f2- | tr -d ' "')
  [ -n "$ENV_URL" ] && NGROK_DOMAIN="$ENV_URL"
fi
if [ -z "$NGROK_DOMAIN" ]; then
  echo "Error: no ngrok domain available." >&2
  echo "  Set CEDAR_NGROK_DOMAIN in your shell rc, or CEDAR_ENGINE_URL in cedar-service/.env." >&2
  exit 1
fi
NGROK_HOST="${NGROK_DOMAIN#https://}"
NGROK_HOST="${NGROK_HOST#http://}"
NGROK_HOST="${NGROK_HOST%/}"

# ---------- summary ----------
echo "════════════════════════════════════════════════════════════"
echo "  cedar-switch-engine"
echo "════════════════════════════════════════════════════════════"
echo "  current : ${CURRENT_PORT:-none}"
echo "  target  : $TARGET_PORT  ($TARGET_LABEL)"
echo "  domain  : $NGROK_HOST"
echo "════════════════════════════════════════════════════════════"

if [ "$CURRENT_PORT" = "$TARGET_PORT" ]; then
  echo "  · ngrok already on port $TARGET_PORT — nothing to do"
  echo "════════════════════════════════════════════════════════════"
  exit 0
fi

# ---------- stop existing ngrok ----------
if [ -n "$NGROK_PID" ]; then
  pkill -x ngrok 2>/dev/null || true
  sleep 0.5
  echo "  ✓ stopped previous ngrok"
fi

# ---------- open new ngrok tab ----------
TERM_APP="Terminal"
if osascript -e 'id of application "iTerm"' >/dev/null 2>&1; then
  TERM_APP="iTerm"
fi

FULL_CMD="cd \"$CEDAR_ROOT\" && printf '\\n=== ngrok ($TARGET_LABEL :$TARGET_PORT) ===\\n' && ngrok http --url=$NGROK_HOST $TARGET_PORT"

# Escape backslashes and double quotes for embedding in an AppleScript
# string literal (same trick start.sh uses).
AS_CMD=$(printf '%s' "$FULL_CMD" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

if [ "$TERM_APP" = "iTerm" ]; then
  osascript <<EOF >/dev/null
tell application "iTerm"
  activate
  if (count of windows) = 0 then
    create window with default profile
    tell current session of current window to write text "$AS_CMD"
  else
    tell current window
      create tab with default profile
      tell current session of current tab to write text "$AS_CMD"
    end tell
  end if
end tell
EOF
else
  osascript <<EOF >/dev/null
tell application "Terminal"
  activate
  if (count of windows) = 0 then
    do script "$AS_CMD"
  else
    tell application "System Events" to keystroke "t" using command down
    delay 0.4
    do script "$AS_CMD" in selected tab of the front window
  end if
end tell
EOF
fi

echo "  ✓ opened ngrok tab on port $TARGET_PORT ($TARGET_LABEL)"
echo "════════════════════════════════════════════════════════════"
