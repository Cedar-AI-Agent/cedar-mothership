# Cedar Dev Workflow Scripts

One-command start/stop/switch for the full local Cedar stack — replaces the four-terminal dance from the root README's *Running Locally* section.

## What's in here

| Script | What it does |
|---|---|
| [`start.sh`](./start.sh) | Brings up docker (postgres + redis + neo4j), then opens a terminal tab per cedar service (`cedar-service`, `cedar-engine`, `cedar-roots`, `cedar-ui`) and one tab for `ngrok`. |
| [`stop.sh`](./stop.sh) | Tears down the four node services and ngrok by walking the process group on each port. Leaves docker containers running by design. |
| [`switch-engine.sh`](./switch-engine.sh) | Flips the ngrok tunnel between port 8080 (cedar-engine) and 9000 (cedar-service) without restarting anything else. |

All three are macOS-only — they drive Terminal/iTerm via `osascript`.

## Prerequisites

| Tool | Why | Install |
|---|---|---|
| **macOS** | Tabs are opened via AppleScript (`osascript`) | n/a |
| **Terminal.app or iTerm2** | One tab per service. iTerm preferred when both are installed. | `brew install --cask iterm2` |
| **Docker (Desktop or daemon)** | Local postgres / redis / neo4j via `docker-compose.pgvector.yml` | [docker.com](https://docker.com) |
| **`ngrok`** | Public tunnel for cedar-engine (or cedar-service) so Vapi/Slack webhooks can reach it | `brew install ngrok` |
| **`gh` CLI** | Used by `setup.sh` to clone the cedar repos. Not used by these scripts directly. | `brew install gh` |
| **Cedar repos cloned** | All `cedar-*` repos must exist as siblings of `cedar-mothership/` (run `./setup.sh` from the repo root) | n/a |
| **Per-repo deps installed** | `npm install` / `pnpm install` in each cedar repo | n/a |
| **`cedar-service/.env`** | The script reads `CEDAR_ENGINE_URL` from here in engine mode | copy from `.env.example` |

## One-time setup

### 1. Get an ngrok static domain

ngrok's free plan gives you one static domain (`*.ngrok-free.dev`). Claim yours from the [ngrok dashboard](https://dashboard.ngrok.com/cloud-edge/domains) and authenticate:

```bash
ngrok config add-authtoken <your-token>
```

### 2. Tell the scripts about your domain

The ngrok domain is resolved in this order:

1. **`CEDAR_ENGINE_URL`** in `cedar-service/.env` — used when running in **engine mode** (default). This is the URL cedar-service is configured to call the engine at, so ngrok must publish on the same domain. Set it once when you configure `cedar-service/.env`:

   ```dotenv
   CEDAR_ENGINE_URL=https://your-static.ngrok-free.dev
   ```

2. **`$CEDAR_NGROK_DOMAIN`** env var — required when running with `--no-engine` (tunnels cedar-service directly), and used as the fallback in engine mode. Set in your shell rc:

   ```bash
   # ~/.zshrc or ~/.bashrc
   export CEDAR_NGROK_DOMAIN="https://your-static.ngrok-free.dev"
   ```

If neither is set, the script exits with a clear error before launching anything.

### 3. Add shell aliases (recommended)

```bash
# ~/.zshrc or ~/.bashrc — adjust path if your mothership lives elsewhere
alias cedar-start='~/Documents/GitHub/cedar/cedar-mothership/scripts/start.sh'
alias cedar-stop='~/Documents/GitHub/cedar/cedar-mothership/scripts/stop.sh'
alias cedar-switch-engine='~/Documents/GitHub/cedar/cedar-mothership/scripts/switch-engine.sh'
```

`source ~/.zshrc` after editing.

### 4. Grant Accessibility permission (one-time, on first run)

The first time you run `start.sh` from a new terminal app, macOS will prompt to allow it to send keystrokes — the script uses `Cmd+T` to open new Terminal tabs. Grant it under **System Settings → Privacy & Security → Accessibility**. (iTerm typically doesn't need this; Terminal.app does.)

## Usage

### Start everything

```bash
cedar-start                    # default: tunnel cedar-engine on :8080
cedar-start --no-engine        # tunnel cedar-service on :9000 instead
cedar-start true               # same as --no-engine
```

What you'll see:
- Docker brought up (or skipped if already running) — postgres, redis, neo4j
- 5 new terminal tabs: `cedar-service`, `cedar-engine`, `cedar-roots`, `cedar-ui`, `ngrok`
- A summary of every URL the stack now exposes

### Stop everything

```bash
cedar-stop
```

Stops the four node services + ngrok by signalling each port's process group (handles npm → tsx watch → node child trees correctly). **Docker containers stay up** — they're cheap to leave running across start/stop cycles.

To bring docker down too:

```bash
cd ~/Documents/GitHub/cedar/cedar-service
docker-compose -f docker-compose.pgvector.yml down
```

### Switch which port ngrok tunnels

```bash
cedar-switch-engine            # toggle 8080 <-> 9000
cedar-switch-engine 8080       # force engine
cedar-switch-engine 9000       # force service
```

Useful when you started in engine mode but need to send a webhook directly to cedar-service (or vice versa) without restarting the whole stack. Stops the existing ngrok process and opens a new tab on the target port.

## Service / port reference

| Service | Port | Started in | Stopped by |
|---|---|---|---|
| cedar-service | 9000 | `npm run dev` | `cedar-stop` |
| cedar-engine | 8080 | `unset OPENAI_API_KEY && pnpm dev` | `cedar-stop` |
| cedar-roots | 3002 | `npm run dev` | `cedar-stop` |
| cedar-ui | 3000 | `npm run dev` | `cedar-stop` |
| ngrok | n/a | `ngrok http --url=$DOMAIN $PORT` | `cedar-stop` |
| postgres | 5432 | `docker-compose up -d` | manual `down` |
| redis | 6379 | `docker-compose up -d` | manual `down` |
| neo4j | 7474 / 7687 | `docker-compose up -d` | manual `down` |

> **`unset OPENAI_API_KEY` for cedar-engine**: when this var is set in the shell, the engine's local OAI client picks it up and clashes with the per-meeting Gemini config. Unsetting forces it to use what's in `cedar-engine/.env`.

## Troubleshooting

### `osascript: -2741` syntax error
The AppleScript string-escape pass got tripped by an unusual character in your path (e.g. a backtick). The script already escapes backslashes and double quotes — file an issue with the failing path and we'll extend it.

### `osascript is not allowed to send keystrokes (-1002)`
You need to grant Terminal/iTerm Accessibility permission once — see step 4 above. After granting, fully quit and reopen the terminal app, then re-run.

### `cedar-stop` reports `still bound after kill — investigate`
Something has the port that isn't a normal child of `npm run dev` — could be a leftover from a previous crash, or a foreign process. Find it manually:

```bash
lsof -i :<port>
kill -9 <pid>
```

### "Error: no ngrok domain available"
Either `cedar-service/.env` doesn't have `CEDAR_ENGINE_URL` set (engine mode) or `$CEDAR_NGROK_DOMAIN` isn't exported in your shell. See step 2.

### Docker containers fail to come up
If you see "port is already allocated" for 5432 / 6379 / 7474, you have a non-docker postgres / redis / neo4j running locally. Stop those first (`brew services stop postgresql`, etc.), or change the docker compose port mappings.

### ngrok rejects the domain
You're using a domain that doesn't belong to your authenticated ngrok account. Either claim that domain in the dashboard, or update your env var to one you own.

## Design notes

- **Why one tab per service** instead of one tmux/zellij window? Most devs already have a terminal app open and Cmd+`number` between tabs is muscle memory. No tooling install required.
- **Why PGID-based killing** in `stop.sh`? `tsx watch` and `next dev` spawn children that bind the port — if you only kill the leaf, npm respawns it. Walking up to the process group and signalling the whole tree fixes that.
- **Why `up -d` is conditional** on container state? `docker-compose up -d` is idempotent (it prints "up-to-date" and exits 0 if everything's running), but skipping it is faster, quieter, and avoids any chance of recreation if the compose file drifted.
- **Why the AppleScript escape sed pass**? Embedded `"` and `\` in the cd path break AppleScript string literals with a `-2741` syntax error. The `sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'` pass takes care of both before the heredoc is interpolated.
