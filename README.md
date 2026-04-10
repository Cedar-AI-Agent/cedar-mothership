# Cedar Mothership

Workspace bootstrap for Cedar's multi-repo development environment. Clones all essential repos, sets up shared [Claude Code](https://claude.ai/claude-code) instructions, and gets new developers productive fast.

## Quick Start

```bash
git clone https://github.com/Cedar-AI-Agent/cedar-mothership.git
cd cedar-mothership
./setup.sh
```

This will:
1. Clone all essential Cedar repos as sibling directories
2. Symlink `../CLAUDE.md` → `cedar-mothership/CLAUDE.md` for Claude Code discovery

## Directory Structure

After setup, your workspace looks like:

```
cedar/
├── CLAUDE.md              ← symlink → cedar-mothership/CLAUDE.md
├── cedar-mothership/      ← this repo
├── cedar-service/         ← Backend API
├── cedar-ui/              ← Frontend Web UI
├── cedar-engine/          ← V5 Meeting Engine
├── cedar-roots/           ← Internal Dashboard
├── cedar-session-replay/  ← Session Replay
├── cedar-infra/           ← Terraform Infrastructure
└── gcp-cloud-functions/   ← Cloud Functions & Data Pipelines
```

## Options

```bash
./setup.sh          # Clone essential repos only (tagged cedar-essential on GitHub)
./setup.sh --all    # Clone ALL repos in the org
```

Repos that already exist locally are skipped — safe to re-run.

## Essential Repos

Managed via the `cedar-essential` GitHub topic. To mark a repo as essential:

```bash
gh repo edit Cedar-AI-Agent/<repo-name> --add-topic cedar-essential
```

## Using with Claude Code

Launch Claude from any project directory — the symlinked `CLAUDE.md` provides cross-project context automatically:

```bash
cd ../cedar-service && claude --add-dir ../cedar-ui
```

See `CLAUDE.md` for architecture overview, integration contracts, and multi-repo workflows.
