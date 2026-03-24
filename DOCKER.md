# Symphony Docker Setup

Run Symphony in isolated Docker containers — one per project if you like.
Your host filesystem stays untouched; the agent gets full permissions inside its sandbox.

---

## Quick Start

```bash
cd docker/

# 1. Set up credentials
cp .env.example .env
# Edit .env — fill in LINEAR_API_KEY and OPENAI_API_KEY at minimum

# 2. Add your WORKFLOW.md
cp ../elixir/WORKFLOW.md workflow/WORKFLOW.md
# Edit workflow/WORKFLOW.md for your project

# 3. Build and run
docker compose build
docker compose up -d

# 4. Check the dashboard
open http://localhost:4000

# 5. View logs
docker compose logs -f
```

---

## Container Layout

| Path inside container       | Purpose                                  |
|-----------------------------|------------------------------------------|
| `/workflow/`                | Your mounted WORKFLOW.md (read-only)     |
| `/workspaces/`              | Symphony clones per-issue repos here     |
| `/repo/`                    | Optional: mount your target repo         |
| `/usr/local/bin/symphony`   | The compiled Symphony escript             |

---

## Running Multiple Projects

Each project gets its own container, credentials, and WORKFLOW.md.

### Option A: Separate directories (recommended)

```
docker/
├── projects/
│   ├── my-app/
│   │   ├── .env
│   │   ├── workflow/
│   │   │   └── WORKFLOW.md
│   │   └── compose.override.yml
│   └── my-api/
│       ├── .env
│       ├── workflow/
│       │   └── WORKFLOW.md
│       └── compose.override.yml
```

Example `compose.override.yml` for a project:

```yaml
services:
  symphony:
    container_name: symphony-my-app   # unique per project
    ports:
      - "4001:4000"                   # unique host port
    volumes:
      - ./workflow:/workflow:ro
      - my-app-workspaces:/workspaces

volumes:
  my-app-workspaces:
```

Run each project:

```bash
# Project A on port 4001
docker compose --env-file projects/my-app/.env \
  -f docker-compose.yml \
  -f projects/my-app/compose.override.yml \
  up -d

# Project B on port 4002
docker compose --env-file projects/my-api/.env \
  -f docker-compose.yml \
  -f projects/my-api/compose.override.yml \
  up -d
```

### Option B: Quick one-liner with docker run

```bash
# Build once from the repo root
docker build -t symphony -f docker/Dockerfile .

# Run per project — change port, env, and workflow mount
docker run -d \
  --name symphony-my-app \
  -e LINEAR_API_KEY=lin_api_xxx \
  -e OPENAI_API_KEY=sk-xxx \
  -p 4001:4000 \
  -v $(pwd)/my-app-workflow:/workflow:ro \
  -v my-app-workspaces:/workspaces \
  symphony
```

---

## Common Commands

```bash
# Build the image
docker compose build

# Start (detached)
docker compose up -d

# Stop
docker compose down

# Stop and destroy volumes (fresh start)
docker compose down -v

# Shell into the running container
docker exec -it symphony-agent bash

# Rebuild after pulling upstream changes
git pull upstream main
docker compose build --no-cache
docker compose up -d
```

---

## Shell Access (Agent Sandbox)

```bash
docker exec -it symphony-agent bash

# Inside you have full access:
#   sudo, apt, pip, npm, git, gh, codex
#   Only /workflow and /workspaces are shared with the host
```

---

## Auth Inside the Container

If you didn't set tokens in .env:

```bash
# GitHub
docker exec -it symphony-agent gh auth login

# Codex (OpenAI)
docker exec -it symphony-agent codex login
```

To persist auth across container restarts, mount a named volume for home:

```yaml
volumes:
  - agent-home:/home/agent
```

---

## Resource Limits

Set in `.env`:

```
CPU_LIMIT=4
MEMORY_LIMIT=8g
```

Or override in docker-compose:

```yaml
deploy:
  resources:
    limits:
      cpus: "8"
      memory: "16g"
```

---

## Network Isolation

Full network access is on by default (needed for git, gh, Linear API).
To fully isolate:

```yaml
services:
  symphony:
    network_mode: none
```

---

## Troubleshooting

**Container exits immediately**
Check logs: `docker compose logs` — usually WORKFLOW.md missing or malformed YAML.

**Port conflict**
Change `SYMPHONY_PORT` in `.env`.

**Permission denied on /workflow**
Ensure workflow/ dir and WORKFLOW.md are readable by UID 1000.

**Auth not persisting across restarts**
Mount a named volume for `/home/agent` (see Auth section above).

**Need to update Symphony**
`git pull upstream main && docker compose build --no-cache && docker compose up -d`
