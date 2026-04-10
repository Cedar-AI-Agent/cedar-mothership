#!/usr/bin/env bash
set -euo pipefail

# Cedar Workspace Setup
# Clones repos as sibling directories and symlinks the shared CLAUDE.md

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
ORG="Cedar-AI-Agent"

# --- Parse args ---
CLONE_ALL=false
for arg in "$@"; do
  case "$arg" in
    --all) CLONE_ALL=true ;;
    -h|--help)
      echo "Usage: ./setup.sh [--all]"
      echo ""
      echo "  (default)  Clone only essential repos (tagged cedar-essential on GitHub)"
      echo "  --all      Clone ALL repos in the $ORG organization"
      exit 0
      ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

# --- Check prerequisites ---
if ! command -v gh &>/dev/null; then
  echo "Error: GitHub CLI (gh) is required. Install: https://cli.github.com"
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "Error: Not authenticated with GitHub CLI. Run: gh auth login"
  exit 1
fi

# --- Fetch repo list ---
echo "Fetching repos from $ORG..."
if [ "$CLONE_ALL" = true ]; then
  REPOS=$(gh repo list "$ORG" --limit 50 --json name,isArchived --jq '.[] | select(.isArchived == false) | .name')
  echo "Mode: all repos"
else
  REPOS=$(gh repo list "$ORG" --topic cedar-essential --limit 50 --json name --jq '.[].name')
  echo "Mode: essential repos only (cedar-essential topic)"
fi

if [ -z "$REPOS" ]; then
  echo "No repos found. Check your GitHub access."
  exit 1
fi

# --- Clone repos ---
echo ""
echo "Cloning into: $PARENT_DIR"
echo "---"

CLONED=0
SKIPPED=0

while IFS= read -r repo; do
  # Skip the mothership repo itself
  if [ "$repo" = "cedar-mothership" ]; then
    continue
  fi

  TARGET="$PARENT_DIR/$repo"

  if [ -d "$TARGET" ]; then
    echo "  [skip] $repo (already exists)"
    SKIPPED=$((SKIPPED + 1))
  else
    echo "  [clone] $repo"
    gh repo clone "$ORG/$repo" "$TARGET" -- --quiet 2>/dev/null || {
      echo "  [warn] Failed to clone $repo — skipping"
      continue
    }
    CLONED=$((CLONED + 1))
  fi
done <<< "$REPOS"

# --- Create CLAUDE.md symlink ---
SYMLINK="$PARENT_DIR/CLAUDE.md"

if [ -L "$SYMLINK" ]; then
  echo ""
  echo "Symlink already exists: $SYMLINK -> $(readlink "$SYMLINK")"
elif [ -f "$SYMLINK" ]; then
  echo ""
  echo "Warning: $SYMLINK is a regular file (not a symlink)."
  echo "Back it up and replace? (y/N)"
  read -r REPLY
  if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    mv "$SYMLINK" "$SYMLINK.bak"
    ln -s cedar-mothership/CLAUDE.md "$SYMLINK"
    echo "Backed up to CLAUDE.md.bak, symlink created."
  else
    echo "Skipped symlink creation."
  fi
else
  ln -s cedar-mothership/CLAUDE.md "$SYMLINK"
  echo ""
  echo "Created symlink: CLAUDE.md -> cedar-mothership/CLAUDE.md"
fi

# --- Summary ---
echo ""
echo "Done! Cloned: $CLONED, Skipped: $SKIPPED"
echo ""
echo "Next steps:"
echo "  cd ../cedar-service && claude --add-dir ../cedar-ui"
