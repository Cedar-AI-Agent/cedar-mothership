# CLAUDE.md - Cedar Workspace

This is the shared workspace for Cedar's projects. It is maintained in the [cedar-mothership](https://github.com/Cedar-AI-Agent/cedar-mothership) repo and symlinked to the parent directory so Claude Code discovers it automatically.

## Projects

| Project | Directory | Purpose |
|---------|-----------|---------|
| cedar-service | `./cedar-service` | Backend API (Node.js, GraphQL, Drizzle ORM) |
| cedar-ui | `./cedar-ui` | Frontend Web UI (Next.js, React, Apollo Client) |
| cedar-engine | `./cedar-engine` | Meeting engine (LangGraph) |
| cedar-roots | `./cedar-roots` | Cedar Roots |
| cedar-session-replay | `./cedar-session-replay` | Session Replay & Observability (standalone, deployed on GCP) |
| cedar-infra | `./cedar-infra` | Infrastructure & deployment (Terraform, GCP) |
| gcp-cloud-functions | `./gcp-cloud-functions` | GCP Cloud Functions |

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
cd cedar-service && claude --add-dir ../cedar-ui
# OR
cd cedar-ui && claude --add-dir ../cedar-service
# For session replay work (include cedar-ui for SDK integration context)
cd cedar-session-replay && claude --add-dir ../cedar-ui
```

## Cross-Project Integration

### GraphQL API Contract

The backend (`cedar-service`) exposes a GraphQL API that the frontend (`cedar-ui`) consumes.

- **Backend schema**: `cedar-service/src/gql/modules/**/*.graphql`
- **Frontend queries/mutations**: `cedar-ui/src/queries/`, `cedar-ui/src/mutations/`, `cedar-ui/src/subscriptions/`
- **Frontend codegen**: Run `npm run codegen` in cedar-ui after backend schema changes

### Environment Endpoints

| Environment | Backend | Frontend |
|-------------|---------|----------|
| Local Dev | `http://localhost:9000/graphql` | `http://localhost:3000` |

### Adding a New API Feature (Typical Workflow)

1. **Backend**: Add/modify GraphQL schema in `cedar-service/src/gql/modules/`
2. **Backend**: Implement resolver and provider logic
3. **Backend**: Test with GraphQL Playground at `localhost:9000/graphql`
4. **Frontend**: Add `.graphql` file in `cedar-ui/src/queries/` or `mutations/`
5. **Frontend**: Run `npm run codegen` to generate TypeScript types
6. **Frontend**: Use generated hooks in React components

### Real-Time Features (WebSocket Subscriptions)

- Backend publishes events via GraphQL subscriptions
- Frontend subscribes using Apollo Client's WebSocket link
- Used for: session updates, network graph changes, live transcripts

### Vapi Voice Integration

- **Backend owns Vapi configuration** (prompts, tools, voice settings)
- **Frontend is thin UI layer** (just connects with assistantId from backend)
- Webhook handler: `cedar-service/src/api/webhooks/` processes Vapi tool calls
- Frontend hook: `cedar-ui/src/hooks/useVapi.ts` wraps Vapi SDK

### Session Replay Integration

cedar-session-replay is a **standalone project** (separate repo, separate deploy on GCP) — not part of cedar-service or cedar-ui.

- **SDK** (`@cedarai/session-replay-sdk`) is published to npm, consumed by cedar-ui
- **cedar-ui integration**: `useCedarReplay` hook in `cedar-ui/src/lib/cedar-replay.tsx`, env var `NEXT_PUBLIC_REPLAY_SERVER_URL`
- **cedar-service link**: SDK uses `cedarSessionId` from cedar-service's `sessions` table. Replay server fetches session context from cedar-service REST API.
- **VAPI link**: Replay server fetches call audio/transcript from VAPI for sessions with `voiceSystem: 'vapi' | 'vapi-langgraph'`
- For full architecture: `cedar-session-replay/docs/architecture.md`

## Common Tasks

### Running Both Projects Locally

Terminal 1 (Backend):
```bash
cd cedar-service && npm run dev
```

Terminal 2 (Frontend):
```bash
cd cedar-ui && npm run dev
```

Terminal 3 (Session Replay - optional):
```bash
cd cedar-session-replay && npm run dev
```

### After Pulling Latest Code

```bash
# Backend
cd cedar-service && npm install

# Frontend
cd cedar-ui && npm install

# Session Replay
cd cedar-session-replay && npm install
```

## Project-Specific Instructions

See individual CLAUDE.md files:
- `./cedar-service/CLAUDE.md` - Backend-specific patterns and conventions
- `./cedar-ui/CLAUDE.md` - Frontend-specific patterns and conventions
- `./cedar-session-replay/CLAUDE.md` - Session replay patterns and conventions

## Setting up Git Worktree

Set up a git worktree for a new or existing branch in the parent directory starting with cedar-service (or cedar-ui) and then the branch name, symlink the .env file, and run npm install.
