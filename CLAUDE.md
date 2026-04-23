# CLAUDE.md - Cedar Workspace

Cross-project context for Claude Code sessions. Maintained in [cedar-mothership](https://github.com/Cedar-AI-Agent/cedar-mothership) and symlinked to the parent directory. For setup and onboarding, see [README.md](./README.md).

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

- Auth: Cloud Run IAM (service → engine), OIDC ID tokens (engine → service), `X-Session-Secret` (per-session). See [Service-to-Service Authentication](#service-to-service-authentication) below.
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

## Service-to-Service Authentication

All internal Cloud Run services use GCP-native auth — no shared API keys between services. Three layers, used together:

### Layer 1 — Cloud Run IAM (`roles/run.invoker`)

The outer gate. Every non-public service requires the caller's SA to hold `roles/run.invoker` on the target.

**The change you'll actually make**: invoker bindings are centralized in the `service_access` module in each environment file (`cedar-infra/terraform/environments/{stage,production}/main.tf`). To allow one service to call another, add an entry — or extend an existing one — in `access_map`:

```hcl
module "service_access" {
  source = "../../modules/service-access"
  # ...
  access_map = {
    cedar-service = ["cedar-engine", "data-muxer", "public-network-data-api"]
    cedar-engine  = ["cedar-service"]
    new-caller    = ["cedar-service"]   # ← e.g. add a new caller
  }
}
```

Apply per environment (stage callers targeting production-only services live in `stage/main.tf`).

- One SA per service per environment, named `{key}-{environment}@{project}.iam.gserviceaccount.com`. Created via the `iam` module in the same environment file.
- Public services (cedar-service, cedar-engine) set `public_access = true` on their `cloud-run-service` block, which adds `allUsers` so browsers and voice providers can reach them. OIDC (layer 2) gates the sensitive endpoints.

### Layer 2 — OIDC ID tokens (service-to-service identity proof)

The caller mints a Google-signed ID token whose audience is the target service URL, and sends it as `Authorization: Bearer <token>`.

**Minting (caller side)** — Node.js pattern used by cedar-engine:

```ts
import { GoogleAuth } from 'google-auth-library';
const auth = new GoogleAuth();
const client = await auth.getIdTokenClient(TARGET_SERVICE_URL); // audience
const headers = await client.getRequestHeaders();               // Authorization: Bearer ...
```

Reference: `cedar-engine/src/bridge/http-client.ts`.

**Verifying (target side)** — depends on the service shape:

- **Fully private** (`public_access = false`): no verification needed. Cloud Run's edge enforces `roles/run.invoker` before the request hits your container, so you can trust the request arrived from an authorized SA. If you want to know *which* caller it was, decode the JWT payload from the `Authorization` header (no signature check needed — the edge already did it).
- **Fully public** (`public_access = true`, exposed to end users): the service authenticates users its own way (user JWTs, session cookies, webhook signing). Service-to-service OIDC usually doesn't apply here — cedar-service is an example.
- **Mixed — public endpoints for non-GCP callers *plus* service-only endpoints** (cedar-engine's situation): the service must be `public_access = true` because endpoints like `/chat/completions` need to be reachable by voice providers (Vapi, ElevenLabs) that don't have GCP credentials. That turns the edge IAM check off for every endpoint, so any endpoint that should be service-to-service only (`POST /sessions`, `POST /meetings`) has to verify the OIDC token in application middleware itself.

For the mixed case, verify in middleware:

```ts
import { OAuth2Client } from 'google-auth-library';
const ticket = await oauth2.verifyIdToken({ idToken, audience: THIS_SERVICE_URL });
const email = ticket.getPayload()?.email;
// Reject unless email === expected caller SA, or ends with @{GCP_PROJECT_ID}.iam.gserviceaccount.com
```

Reference: `cedar-engine/src/server/app.ts` (`requireServiceAuth`). Gate the middleware on `GCP_PROJECT_ID` being set so local dev works without real GCP credentials.

### Layer 3 — Per-session / webhook secrets

Different purpose — *these are not service identity*; they authorize a specific session or verify an external webhook:

- **`X-Session-Secret`** — opaque per-session bearer generated when a session is created; required on session-scoped endpoints (`/sessions/:id/state`, `/chat/completions`). Used by browsers and voice providers that don't have SAs.
- **Webhook signing** — `SLACK_SIGNING_SECRET`, `STRIPE_WEBHOOK_SECRET`, `ELEVENLABS_WEBHOOK_SECRET`, `BLAND_AI_WEBHOOK_SECRET`. Verified at handler level.

### Ingress and IAP — when to use what

`ingress` controls who can reach the Cloud Run URL at the network layer; IAP (Identity-Aware Proxy) handles the Google OAuth dance in the browser. Pick based on the service's shape and who actually needs to reach it:

| Service shape | Ingress | Auth | IAP |
|---|---|---|---|
| Internal backend, accessed by devs via curl / Insomnia | `INGRESS_TRAFFIC_ALL` | Cloud Run IAM + OIDC (layers 1 + 2) | No |
| Internal service with its own browser frontend, used by Cedar staff | `INTERNAL_AND_CLOUD_LOAD_BALANCING` | Cloud Run IAM + OIDC + IAP, shared IAP cookie across frontend and backend | Yes |

**Why skip IAP on backend-only services**: IAP's main value is handling the Google OAuth flow automatically for browsers. If devs are reaching the service via curl/Insomnia, IAP just adds friction without buying real security — the attack surface is roughly the same whether the HTTP port is exposed at Cloud Run ingress or behind a load balancer.

**When IAP earns its keep**: services with a browser UI meant for Cedar staff. Pair `INTERNAL_AND_CLOUD_LOAD_BALANCING` ingress (so the LB is the only path in) with a shared IAP cookie across the frontend and any backend it calls, so users authenticate once.

### Common task — letting service A call service B

Edit `cedar-infra/terraform/environments/{stage,production}/main.tf` and add B to A's list in the `service_access` module's `access_map`. Apply per environment. No code change needed if A is already minting OIDC tokens for the call.

### Standing up a new service

1. In the environment file, add the service's SA to the `iam` module entry with the GCP roles it needs (Cloud SQL client, BigQuery, etc.).
2. Add the new `cloud-run-service` module block. Set `public_access = true` only if non-GCP callers (end users, third-party webhooks, voice providers) must reach it directly — otherwise leave it private and let Cloud Run's edge enforce IAM.
3. In `service_access`'s `access_map`, list this service as a caller of anything it needs to invoke, and add it as a target of any existing service that needs to invoke it.
4. Pick `ingress` and decide on IAP using the table above — default `INGRESS_TRAFFIC_ALL` with no IAP for an internal backend.
5. Inject target service URLs via Terraform env vars (`CEDAR_SERVICE_URL`, etc.) — don't hardcode. Audience matching depends on this.
6. In the caller's code, use `GoogleAuth.getIdTokenClient(targetUrl)` to mint OIDC tokens — never share secrets between services.
7. **Only if the new service is the mixed case** (public for non-GCP callers but with some service-only endpoints): add middleware on those endpoints that verifies the OIDC token (audience = its own public URL, caller email matches an allowlist or the project's SA suffix). Gate it on `GCP_PROJECT_ID` being set so local dev stays simple. Fully-private services get this for free from the edge.
8. For callers that run outside GCP (browsers, voice providers, webhooks), use layer 3 (session secrets / signed webhooks), not OIDC.

### Known gap

cedar-service → cedar-engine (`POST /sessions`) currently relies on Cloud Run IAM only — no OIDC token is minted. The verification code on the engine side exists; the minting on the service side does not. Adding it would bring this call to parity with engine → service.

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

## Runtime Configuration (Env Vars & Secrets)

Env vars and secrets are managed via each service's `cloud-run.yaml` — **not Terraform, not manual gcloud commands**. The file is applied during CI deploys.

**Do not run `gcloud run services update` manually to change env vars or secrets.** Changes made by hand will be overwritten on the next deploy. All changes go through `cloud-run.yaml`.

- **Adding an env var:** Add to `cloud-run.yaml`, deploy with `--update-config`
- **Adding a secret:** Create value in Secret Manager, add name to `cloud-run.yaml`, deploy with `--update-config`
- **Removing:** Remove the line from `cloud-run.yaml`, deploy with `--update-config`

**Secret naming convention:** `{service-name}-{environment}_{SECRET_NAME}`

**Rules:**
- Each service owns its own secrets — never share across services
- If two services need the same API key, create separate secrets under each prefix
- See `cedar-infra/README.md` for full details

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
