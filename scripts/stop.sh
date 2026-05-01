#!/bin/bash
#
# Cedar Stop Script
# -----------------
# Stops every Cedar dev service started by ./start.sh.
#
# Strategy:
#   1. Find the PID bound to each service port via lsof.
#   2. Walk up to that PID's process group (PGID) and signal the whole
#      group so npm / pnpm / tsx-watch / next-server parents go down with
#      the leaf node process (otherwise they stay alive and may rebind).
#   3. Fall back to a directory-scoped pkill -f for any stragglers (e.g.
#      tsx watch parents that survived because they were in a different
#      process group than the leaf).
#   4. SIGTERM first, then SIGKILL anything still running after a short
#      grace period.
#
# Note: this stops the node services and ngrok only. The docker containers
# (postgres / redis / neo4j) are LEFT RUNNING — they're cheap to keep up
# and you usually want them across multiple start/stop cycles. Bring them
# down explicitly with:
#   cd ../cedar-service && docker-compose -f docker-compose.pgvector.yml down
#
# Usage: ./stop.sh

# Don't `set -e` — every kill attempt should still run if one fails.

# Script lives in cedar-mothership/scripts/. CEDAR_ROOT is two dirs up —
# the workspace dir that holds all cedar-* sibling repos.
CEDAR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "════════════════════════════════════════════════════════════"
echo "  Cedar — stopping all services"
echo "════════════════════════════════════════════════════════════"

# Collect process groups owning a TCP port. Returns a deduped, space-
# separated list. Empty output means nothing is bound.
pgids_on_port() {
  local port="$1"
  local pids pgids="" pid pgid
  pids=$(lsof -ti tcp:"$port" 2>/dev/null)
  for pid in $pids; do
    pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$pgid" ] && pgids="$pgids $pgid"
  done
  echo "$pgids" | tr ' ' '\n' | awk 'NF' | sort -u | tr '\n' ' '
}

# Send a signal to every PGID, swallowing "no such process" errors.
signal_pgids() {
  local sig="$1"; shift
  local pgid
  for pgid in "$@"; do
    kill -"$sig" -- -"$pgid" 2>/dev/null
  done
}

stop_service() {
  local port="$1"
  local label="$2"
  local dir="$3"

  local pgids
  pgids=$(pgids_on_port "$port")

  if [ -z "$pgids" ]; then
    # Nothing on the port — but a parent (e.g. `tsx watch` between
    # respawns) might still be alive in that service's directory.
    if [ -n "$dir" ] && pgrep -f "$dir" >/dev/null 2>&1; then
      pkill -TERM -f "$dir" 2>/dev/null
      sleep 0.3
      pkill -KILL -f "$dir" 2>/dev/null
      echo "  ✓ stopped $label (no listener, killed parents in $dir)"
    else
      echo "  · $label (port $port) not running"
    fi
    return
  fi

  # SIGTERM the whole tree so children get a chance to clean up.
  signal_pgids TERM $pgids
  sleep 0.5

  # Anything still bound? SIGKILL it.
  if [ -n "$(lsof -ti tcp:"$port" 2>/dev/null)" ]; then
    signal_pgids KILL $pgids
    sleep 0.2
  fi

  # Belt-and-suspenders: any other process whose command line mentions
  # this service's directory (e.g. `tsx watch /Users/.../cedar-service/...`).
  if [ -n "$dir" ] && pgrep -f "$dir" >/dev/null 2>&1; then
    pkill -KILL -f "$dir" 2>/dev/null
  fi

  if [ -n "$(lsof -ti tcp:"$port" 2>/dev/null)" ]; then
    echo "  ✗ $label (port $port) still bound after kill — investigate"
  else
    echo "  ✓ stopped $label (port $port)"
  fi
}

stop_service 9000 "cedar-service" "$CEDAR_ROOT/cedar-service"
stop_service 8080 "cedar-engine"  "$CEDAR_ROOT/cedar-engine"
stop_service 3002 "cedar-roots"   "$CEDAR_ROOT/cedar-roots"
stop_service 3000 "cedar-ui"      "$CEDAR_ROOT/cedar-ui"

# ngrok runs on its own — kill by process name.
if pgrep -x ngrok >/dev/null; then
  pkill -x ngrok
  echo "  ✓ stopped ngrok"
else
  echo "  · ngrok not running"
fi

echo "════════════════════════════════════════════════════════════"
echo "  Done."
echo "════════════════════════════════════════════════════════════"
