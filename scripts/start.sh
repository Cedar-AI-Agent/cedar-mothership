#!/bin/bash
#
# Cedar Start Script
# ------------------
# Opens a terminal tab per Cedar service and starts them all in dev mode.
# Also opens a tab for ngrok, tunneling either port 8080 (cedar-engine) or
# port 9000 (cedar-service) depending on the noEngine flag, and brings up
# the local docker stack (postgres + redis + neo4j) before launching.
#
# Usage:
#   ./start.sh                  # noEngine defaults to false -> ngrok 8080
#   ./start.sh false            # noEngine = false           -> ngrok 8080
#   ./start.sh true             # noEngine = true            -> ngrok 9000
#   ./start.sh --no-engine      # same as `true`
#
# Tabs are opened in iTerm2 when available, otherwise Terminal.app.
#
# Requirements (see scripts/README.md for full setup):
#   - macOS (uses osascript + Terminal/iTerm)
#   - All cedar repos cloned as siblings of cedar-mothership (run setup.sh)
#   - Docker, ngrok, gh CLI installed
#   - cedar-service/.env populated (CEDAR_ENGINE_URL is read from here)
#   - $CEDAR_NGROK_DOMAIN env var set if running with --no-engine

set -e

# ---------- args ----------
NO_ENGINE="false"
case "${1:-}" in
  true|--no-engine|-n) NO_ENGINE="true" ;;
  false|"") NO_ENGINE="false" ;;
  -h|--help)
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    echo "Usage: $0 [true|false|--no-engine]" >&2
    exit 1
    ;;
esac

# Script lives in cedar-mothership/scripts/. CEDAR_ROOT is two dirs up —
# the workspace dir that holds all cedar-* sibling repos.
CEDAR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ---------- ngrok config ----------
# Resolve the ngrok domain. Priority:
#   1. CEDAR_ENGINE_URL from cedar-service/.env (engine mode only — must match
#      whatever cedar-service is configured to call the engine at)
#   2. $CEDAR_NGROK_DOMAIN env var (per-dev personal static domain)
# Fail with a helpful message if neither is available.
NGROK_DOMAIN="${CEDAR_NGROK_DOMAIN:-}"

if [ "$NO_ENGINE" = "true" ]; then
  # Skipping the engine: tunnel cedar-service directly. Domain MUST come
  # from the env var (cedar-service/.env doesn't speak to its own URL).
  NGROK_PORT=9000
  if [ -z "$NGROK_DOMAIN" ]; then
    echo "Error: CEDAR_NGROK_DOMAIN is not set." >&2
    echo "  Set it in your shell rc:" >&2
    echo "    export CEDAR_NGROK_DOMAIN=\"https://your-static.ngrok-free.dev\"" >&2
    exit 1
  fi
else
  # Default path: tunnel cedar-engine. Prefer CEDAR_ENGINE_URL from
  # cedar-service/.env so the tunnel and the service agree.
  NGROK_PORT=8080
  ENV_FILE="$CEDAR_ROOT/cedar-service/.env"
  if [ -f "$ENV_FILE" ]; then
    ENV_URL=$(grep -E "^CEDAR_ENGINE_URL=" "$ENV_FILE" | tail -n1 | cut -d'=' -f2- | tr -d ' "')
    if [ -n "$ENV_URL" ]; then
      NGROK_DOMAIN="$ENV_URL"
      echo "✓ CEDAR_ENGINE_URL picked up from cedar-service/.env"
    fi
  fi
  if [ -z "$NGROK_DOMAIN" ]; then
    echo "Error: no ngrok domain available." >&2
    echo "  Either set CEDAR_ENGINE_URL in cedar-service/.env (preferred for engine mode)," >&2
    echo "  or set CEDAR_NGROK_DOMAIN in your shell rc:" >&2
    echo "    export CEDAR_NGROK_DOMAIN=\"https://your-static.ngrok-free.dev\"" >&2
    exit 1
  fi
fi

# ngrok --url= wants just the hostname (no scheme, no trailing slash).
NGROK_HOST="${NGROK_DOMAIN#https://}"
NGROK_HOST="${NGROK_HOST#http://}"
NGROK_HOST="${NGROK_HOST%/}"

# ---------- terminal detection ----------
# Prefer iTerm2 if installed, otherwise fall back to Terminal.app.
TERM_APP="Terminal"
if osascript -e 'id of application "iTerm"' >/dev/null 2>&1; then
  TERM_APP="iTerm"
fi

open_tab() {
  local label="$1"
  local dir="$2"
  local cmd="$3"

  # Build the shell command. Quote $dir to handle paths with spaces.
  local full_cmd="cd \"$dir\" && printf '\\n=== %s ===\\n' '$label' && $cmd"

  # Escape backslashes and double quotes for embedding in an AppleScript
  # string literal. Without this, the embedded "..." around $dir terminates
  # the AppleScript string early and triggers a -2741 syntax error.
  local as_cmd
  as_cmd=$(printf '%s' "$full_cmd" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

  if [ "$TERM_APP" = "iTerm" ]; then
    osascript <<EOF >/dev/null
tell application "iTerm"
  activate
  if (count of windows) = 0 then
    create window with default profile
    tell current session of current window to write text "$as_cmd"
  else
    tell current window
      create tab with default profile
      tell current session of current tab to write text "$as_cmd"
    end tell
  end if
end tell
EOF
  else
    # Terminal.app: Cmd+T into the front window if one exists, else open new.
    osascript <<EOF >/dev/null
tell application "Terminal"
  activate
  if (count of windows) = 0 then
    do script "$as_cmd"
  else
    tell application "System Events" to keystroke "t" using command down
    delay 0.4
    do script "$as_cmd" in selected tab of the front window
  end if
end tell
EOF
  fi
  echo "  ✓ $label"
}

# ---------- launch ----------
echo "════════════════════════════════════════════════════════════"
echo "  Cedar — starting all services ($TERM_APP)"
echo "════════════════════════════════════════════════════════════"
echo "  noEngine : $NO_ENGINE"
echo "  ngrok    : $NGROK_HOST -> localhost:$NGROK_PORT"
echo "════════════════════════════════════════════════════════════"
echo

# ---------- docker (postgres + redis + neo4j) ----------
# Bring infra up before launching services so they don't race the DB.
# `up -d` is technically idempotent, but if all containers are already running
# we skip it: faster, quieter, and avoids any chance of recreation on drift.
DOCKER_DIR="$CEDAR_ROOT/cedar-service"
COMPOSE_FILE="docker-compose.pgvector.yml"

echo "Checking docker services (postgres, redis, neo4j)..."
defined_count=$(cd "$DOCKER_DIR" && docker-compose -f "$COMPOSE_FILE" ps --services 2>/dev/null | wc -l | tr -d ' ')
running_count=$(cd "$DOCKER_DIR" && docker-compose -f "$COMPOSE_FILE" ps --services --filter "status=running" 2>/dev/null | wc -l | tr -d ' ')

if [ "$defined_count" -gt 0 ] && [ "$running_count" = "$defined_count" ]; then
  echo "  ✓ docker services already running ($running_count/$defined_count) — skipping"
else
  echo "  Starting docker services ($running_count/$defined_count currently up)..."
  if (cd "$DOCKER_DIR" && docker-compose -f "$COMPOSE_FILE" up -d); then
    echo "  ✓ docker services up"
  else
    echo "  ✗ docker-compose failed — services may not start correctly"
  fi
fi
echo

# `unset OPENAI_API_KEY` for cedar-engine: when this var is set in the shell,
# the engine's local-dev OAI client picks it up and clashes with the per-meeting
# Gemini config. Unsetting forces it to use what's in cedar-engine/.env.
open_tab "cedar-service" "$CEDAR_ROOT/cedar-service" "npm run dev"
open_tab "cedar-engine"  "$CEDAR_ROOT/cedar-engine"  "unset OPENAI_API_KEY && pnpm dev"
open_tab "cedar-roots"   "$CEDAR_ROOT/cedar-roots"   "npm run dev"
open_tab "cedar-ui"      "$CEDAR_ROOT/cedar-ui"      "npm run dev"
open_tab "ngrok"         "$CEDAR_ROOT"               "ngrok http --url=$NGROK_HOST $NGROK_PORT"

echo
echo "════════════════════════════════════════════════════════════"
echo "  All services launched in $TERM_APP tabs"
echo "════════════════════════════════════════════════════════════"
echo "  cedar-service : http://localhost:9000"
echo "  cedar-engine  : http://localhost:8080"
echo "  cedar-roots   : http://localhost:3002"
echo "  cedar-ui      : http://localhost:3000"
echo "  ngrok         : $NGROK_DOMAIN  ->  localhost:$NGROK_PORT"
echo
echo "  docker (in cedar-service/docker-compose.pgvector.yml):"
echo "    postgres    : localhost:5432"
echo "    redis       : localhost:6379"
echo "    neo4j       : http://localhost:7474  (bolt :7687)"
echo
echo "  Stop everything:  ./stop.sh"
echo "════════════════════════════════════════════════════════════"
