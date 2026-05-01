# Cedar Mothership

Workspace bootstrap for Cedar's multi-repo development environment. Clones all essential repos, sets up shared [Claude Code](https://claude.ai/claude-code) instructions, and gets new developers productive fast.

## What is Cedar?

Cedar is an AI-powered recruiting agent that leverages a company's internal employee network to farm, field, and source high-quality referrals. It operates through Slack, voice calls, and a web UI.

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
├── cedar-service/         ← Backend API (Node.js, GraphQL, Drizzle ORM)
├── cedar-ui/              ← Frontend Web UI (Next.js, React, Apollo Client)
├── cedar-engine/          ← V5 Meeting Engine (Hono, LangGraph)
├── cedar-roots/           ← Internal Dashboard (Next.js, Tailwind)
├── cedar-session-replay/  ← Session Replay & Observability
├── cedar-infra/           ← Terraform Infrastructure (GCP)
└── gcp-cloud-functions/   ← Cloud Functions & Data Pipelines
```

## Setup Options

```bash
./setup.sh          # Clone essential repos only (tagged cedar-essential on GitHub)
./setup.sh --all    # Clone ALL repos in the org
```

Repos that already exist locally are skipped — safe to re-run.

## Running Locally

The fast path is the workflow scripts in [`scripts/`](./scripts/) — one command brings up docker (postgres + redis + neo4j), all four cedar services, and ngrok in tabbed terminals:

```bash
./scripts/start.sh           # bring everything up
./scripts/stop.sh            # tear it back down
./scripts/switch-engine.sh   # flip ngrok between engine (:8080) and service (:9000)
```

See [`scripts/README.md`](./scripts/README.md) for prerequisites (ngrok static domain, docker, alias setup) and full usage.

If you'd rather start things by hand:

```bash
# Backend (Terminal 1)
cd cedar-service && npm run dev          # http://localhost:9000/graphql

# Frontend (Terminal 2)
cd cedar-ui && npm run dev               # http://localhost:3000

# Engine (Terminal 3 — if working on meetings)
cd cedar-engine && pnpm dev              # http://localhost:8080

# Internal Dashboard (Terminal 4 — if working on ops)
cd cedar-roots && npm run dev            # http://localhost:3001

# Session Replay (optional)
cd cedar-session-replay && npm run dev
```

## Using with Claude Code

The symlinked `CLAUDE.md` provides cross-project context automatically. Launch Claude from any project and add related repos:

```bash
# Backend + Frontend (most common)
cd cedar-service && claude --add-dir ../cedar-ui

# Frontend + Backend
cd cedar-ui && claude --add-dir ../cedar-service

# Engine work (needs backend for bridge contract)
cd cedar-engine && claude --add-dir ../cedar-service

# Internal dashboard (needs backend for API context)
cd cedar-roots && claude --add-dir ../cedar-service
```

## Architecture & Integration Docs

For detailed architecture, cross-project integration contracts, and multi-repo workflows, see **[CLAUDE.md](./CLAUDE.md)**. It's written for Claude Code but equally useful for developers understanding how services connect.

## Managing Essential Repos

Essential repos are managed via the `cedar-essential` GitHub topic:

```bash
# Add a repo
gh repo edit Cedar-AI-Agent/<repo-name> --add-topic cedar-essential

# Remove a repo
gh repo edit Cedar-AI-Agent/<repo-name> --remove-topic cedar-essential

# List essential repos
gh repo list Cedar-AI-Agent --topic cedar-essential
```

## Project Links

| Project | Repo |
|---------|------|
| cedar-service | [Cedar-AI-Agent/cedar-service](https://github.com/Cedar-AI-Agent/cedar-service) |
| cedar-ui | [Cedar-AI-Agent/cedar-ui](https://github.com/Cedar-AI-Agent/cedar-ui) |
| cedar-engine | [Cedar-AI-Agent/cedar-engine](https://github.com/Cedar-AI-Agent/cedar-engine) |
| cedar-roots | [Cedar-AI-Agent/cedar-roots](https://github.com/Cedar-AI-Agent/cedar-roots) |
| cedar-session-replay | [Cedar-AI-Agent/cedar-session-replay](https://github.com/Cedar-AI-Agent/cedar-session-replay) |
| cedar-infra | [Cedar-AI-Agent/cedar-infra](https://github.com/Cedar-AI-Agent/cedar-infra) |
| gcp-cloud-functions | [Cedar-AI-Agent/gcp-cloud-functions](https://github.com/Cedar-AI-Agent/gcp-cloud-functions) |
