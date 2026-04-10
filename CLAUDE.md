# CLAUDE.md - Cedar Workspace

This is the shared workspace for Cedar's projects. It is maintained in the [cedar-mothership](https://github.com/Cedar-AI-Agent/cedar-mothership) repo and symlinked to the parent directory so Claude Code discovers it automatically.

## Projects

| Project | Directory | Purpose | Tech Stack |
|---------|-----------|---------|------------|
| cedar-service | `./cedar-service` | Backend API — GraphQL, REST, Slack bot, voice webhooks | Node.js, Express, Drizzle ORM, PostgreSQL |
| cedar-ui | `./cedar-ui` | Customer-facing web UI — meeting sessions, network graphs | Next.js, React, Apollo Client |
| cedar-engine | `./cedar-engine` | V5 meeting engine microservice — manifest-driven AI conversations | Hono, LangGraph, OpenAI/Gemini, PostgreSQL |
| cedar-roots | `./cedar-roots` | Internal dashboard — pre-call automation, post-call processing | Next.js 15, React 19, Apollo Client, Tailwind 4 |
| cedar-session-replay | `./cedar-session-replay` | Session replay & observability (standalone, deployed on GCP) | Standalone service, npm SDK |
| cedar-infra | `./cedar-infra` | Infrastructure-as-Code — all GCP resources | Terraform, CircleCI |
| gcp-cloud-functions | `./gcp-cloud-functions` | Distributed cloud functions — enrichment, scraping, data sync | TypeScript, Cloud Run, Cloud Functions, Pub/Sub |

## Setup

New developer? Run the setup script:

```bash
cd cedar-mothership
./setup.sh          # clones essential repos (tagged cedar-essential on GitHub)
./setup.sh --all    # clones ALL org repos
```

The script:
1. Clones repos as sibling directories (skips any that already exist)
2. Creates a symlink `../CLAUDE.md -> cedar-mothership/CLAUDE.md`

## Working with Multiple Projects

When starting Claude Code, use `--add-dir` to include related projects:
```bash
# Backend + Frontend (most common)
cd cedar-service && claude --add-dir ../cedar-ui

# Frontend + Backend
cd cedar-ui && claude --add-dir ../cedar-service

# Engine work (needs backend for bridge contract)
cd cedar-engine && claude --add-dir ../cedar-service

# Internal dashboard (needs backend for API context)
cd cedar-roots && claude --add-dir ../cedar-service

# Session replay (needs frontend for SDK integration context)
cd cedar-session-replay && claude --add-dir ../cedar-ui

# Infrastructure (include services for context on what's deployed)
cd cedar-infra && claude --add-dir ../cedar-service --add-dir ../cedar-engine
```

## Architecture Overview

```
                    ┌─────────────┐
                    │  cedar-ui   │  Customer-facing web UI
                    └──────┬──────┘
                           │ GraphQL/WS + Voice SSE
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
     ┌────────────┐  ┌───────────┐  ┌────────────┐
     │cedar-service│  │cedar-engine│  │cedar-roots │  Internal dashboard
     │  (API hub)  │  │ (V5 meets) │  │(ops tool)  │
     └──┬───┬──┬──┘  └─────┬─────┘  └──────┬─────┘
        │   │  │            │               │
        │   │  │   Bridge   │               │ GraphQL + REST proxy
        │   │  └────────────┘               │
        │   │                               │
        │   └───────────────────────────────┘
        │
        ▼
┌───────────────────┐     ┌──────────────────────┐
│gcp-cloud-functions│     │cedar-session-replay   │
│(enrichment, sync) │     │(replay server + SDK)  │
└───────────────────┘     └──────────────────────┘

        All deployed via cedar-infra (Terraform → GCP)
```

## Cross-Project Integration

### cedar-service ↔ cedar-ui (GraphQL API Contract)

The backend exposes a GraphQL API that the frontend consumes.

- **Backend schema**: `cedar-service/src/gql/modules/**/*.graphql`
- **Frontend queries/mutations**: `cedar-ui/src/queries/`, `cedar-ui/src/mutations/`, `cedar-ui/src/subscriptions/`
- **Frontend codegen**: Run `npm run codegen` in cedar-ui after backend schema changes
- **Real-time**: Backend publishes events via GraphQL subscriptions (Redis pub/sub). Frontend subscribes via Apollo Client WebSocket link. Used for: session updates, network graph changes, live transcripts.

### cedar-service ↔ cedar-engine (Bridge Contract)

cedar-engine is a standalone microservice. cedar-service orchestrates it via HTTP:

| Direction | Endpoint | Purpose |
|-----------|----------|---------|
| service → engine | `POST /sessions` | Create engine session with manifest + data bundle |
| service → engine | `POST /chat/completions` | Proxy voice turns (SSE stream) |
| engine → service | `POST /api/engine-callback/complete` | Notify session end + outputs |
| engine → service | `POST /api/data-query` | Mid-call data lookups (network search, contacts, pipeline) |

- Auth: `X-Service-Auth-Key` header (service-to-service), `X-Session-Secret` (per-session)
- Engine returns SSE streams with content + `updateUI` tool calls for the frontend

### cedar-service ↔ cedar-roots (Internal Dashboard)

cedar-roots is a thin UI — cedar-service owns all business logic.

- **GraphQL**: `automationRuns`, `automationRunDetail`, `deleteAutomationRun`, subscriptions for real-time updates
- **REST proxies**: cedar-roots Next.js API routes proxy to cedar-service (`/referral-farming/*`, `/granola/*`)
- **Auth**: Google OAuth restricted to `@getcedar.ai` domain
- **Domain**: `roots.getcedar.ai`

### cedar-service ↔ gcp-cloud-functions

Cloud functions handle async enrichment/scraping and call back to cedar-service:

- **Functions → cedar-service**: HTTP calls for contact upsert, company find-or-create, employee ingestion
- **cedar-service → functions**: Triggers via Pub/Sub topics and Cloud Tasks
- **Shared data**: AlloyDB (PostgreSQL), BigQuery, GCP Secret Manager
- **Key functions**: airtop-linkedin-enrichment, public-network-data-api, public-network-data-sync, job-scraper, company-job-board-discovery

### cedar-ui ↔ cedar-engine (Voice Sessions)

During active voice meetings, cedar-ui communicates with cedar-engine:

- Voice turns flow: `cedar-ui → voice provider (Vapi/ElevenLabs) → cedar-service REST → cedar-engine`
- UI clicks as system messages: `cedar-ui → sendSystemMessage() → voice provider → cedar-engine`
- UI state updates: cedar-engine embeds `updateUI` tool calls in SSE response stream
- Non-voice UI events: `cedar-ui → cedar-service GraphQL (processEngineEvent) → cedar-engine`

### cedar-ui ↔ cedar-session-replay

- **SDK** (`@cedarai/session-replay-sdk`) published to npm, consumed by cedar-ui
- **Integration**: `useCedarReplay` hook in `cedar-ui/src/lib/cedar-replay.tsx`
- **Link**: SDK uses `cedarSessionId` from cedar-service's sessions table
- **Audio**: Replay server fetches call audio/transcript from Vapi for voice sessions

### cedar-infra → All Services

cedar-infra deploys everything via Terraform:

| Service | Cloud Run | Environment |
|---------|-----------|-------------|
| cedar-service | `cedar-service-{stage,production}` | stage, production |
| cedar-engine | `cedar-engine-{stage,production}` | stage, production |
| cedar-ui | `cedar-ui-{stage,production}` | stage, production |

Also manages: Cloud SQL, Secret Manager, IAM, Cloud Tasks, Pub/Sub, Cloud Scheduler, DNS, monitoring.

- **GCP Project**: `diesel-polymer-426322-j2` (us-west1)
- **CI/CD**: CircleCI — PR → plan, main → apply shared → apply stage → manual approval → apply production

### gcp-cloud-functions (Internal Architecture)

Functions are independently deployable, each with its own Terraform config:

- **Deployment**: CircleCI detects changed directories → Terraform apply per function
- **Communication**: Pub/Sub topics for async decoupling between functions
- **Key services** (Cloud Run): `public-network-data-api` (REST API for AlloyDB data), `public-network-data-sync` (hourly MixRank → BigQuery → AlloyDB pipeline), `e2e-simulation-service`

## Environment Endpoints

| Environment | cedar-service | cedar-ui | cedar-roots | cedar-engine |
|-------------|---------------|----------|-------------|--------------|
| Local Dev | `http://localhost:9000/graphql` | `http://localhost:3000` | `http://localhost:3001` | `http://localhost:8080` |
| Production | Cloud Run | Cloud Run | `roots.getcedar.ai` | Cloud Run |

## Adding a New API Feature (Typical Workflow)

1. **Backend**: Add/modify GraphQL schema in `cedar-service/src/gql/modules/`
2. **Backend**: Implement resolver and provider logic
3. **Backend**: Test with GraphQL Playground at `localhost:9000/graphql`
4. **Frontend**: Add `.graphql` file in `cedar-ui/src/queries/` or `mutations/`
5. **Frontend**: Run `npm run codegen` to generate TypeScript types
6. **Frontend**: Use generated hooks in React components

## Adding a New Meeting Type

1. **cedar-engine**: Define manifest in `src/manifests/` (phases, tools, data contracts, prompts)
2. **cedar-service**: Register meeting type, add session creation logic
3. **cedar-service**: Add bridge integration (data bundle, callback handling)
4. **cedar-ui**: Add UI screens and voice integration for the new meeting type

## Common Tasks

### Running Projects Locally

```bash
# Backend (Terminal 1)
cd cedar-service && npm run dev

# Frontend (Terminal 2)
cd cedar-ui && npm run dev

# Engine (Terminal 3 — if working on meetings)
cd cedar-engine && pnpm dev

# Internal Dashboard (Terminal 4 — if working on ops)
cd cedar-roots && npm run dev

# Session Replay (optional)
cd cedar-session-replay && npm run dev
```

### After Pulling Latest Code

```bash
cd cedar-service && npm install
cd cedar-ui && npm install
cd cedar-engine && pnpm install
cd cedar-roots && npm install
cd cedar-session-replay && npm install
```

## Project-Specific Instructions

See individual CLAUDE.md files:
- `./cedar-service/CLAUDE.md` — Backend patterns, providers, database, git conventions
- `./cedar-ui/CLAUDE.md` — Frontend patterns and conventions
- `./cedar-engine/CLAUDE.md` — Engine manifest patterns (if present; see `MANIFEST_GOTCHAS.md`)
- `./cedar-roots/CLAUDE.md` — Internal dashboard patterns
- `./cedar-session-replay/CLAUDE.md` — Session replay patterns
- `./gcp-cloud-functions/CLAUDE.md` — Cloud functions code style

## Setting up Git Worktree

Set up a git worktree for a new or existing branch in the parent directory starting with cedar-service (or cedar-ui) and then the branch name, symlink the .env file, and run npm install.
