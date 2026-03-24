# Symphony Docker Setup

Run Symphony in isolated Docker containers — one per repo/Linear project.
The `setup.sh` script handles everything: config, port allocation, auth, and lifecycle.

---

## Quick Start

```bash
cd docker/
./setup.sh
```

The interactive setup will walk you through:
1. Naming your project
2. Providing your repo clone URL
3. Providing your Linear project slug + API key
4. Setting resource limits (defaults: 1 CPU / 2GB RAM)
5. Building the Docker image (first time only)
6. Authenticating Codex and GitHub inside the container

Ports are assigned automatically — you never have to think about them.

---

## Before You Start

### 1. Harness Engineering

Your codebase should follow harness engineering practices. Symphony works best
with repos that have good test coverage, CI, and clear contribution guidelines.

See: https://openai.com/index/harness-engineering/

### 2. Linear Workflow States

Add these custom states in Linear under Team Settings → Workflow → "Started" category:
- **Rework**
- **Human Review**
- **Merging**

These are required for Symphony's status machine. They must be created manually
in the Linear UI — there's no API for this.

### 3. Codex Skills (optional but recommended)

Copy the `.codex/skills/` directory from this repo into your target repo:

```bash
cp -r .codex/skills/ /path/to/your-repo/.codex/skills/
```

This gives the agent skills for: commit, push, pull, land, linear, debug.

### 4. WORKFLOW.md

The setup script generates a starter WORKFLOW.md for your project. You can
customise it at `docker/projects/<name>/workflow/WORKFLOW.md`. For the full
reference, see `elixir/WORKFLOW.md` in this repo.

---

## Managing Projects

```bash
./setup.sh --list              # List all projects + status
./setup.sh --start <name>      # Start (picks up where it left off)
./setup.sh --stop <name>       # Stop a project
./setup.sh --stop-all          # Stop all symphony containers
./setup.sh --logs <name>       # Tail logs
./setup.sh --shell <name>      # Shell into container
./setup.sh --remove <name>     # Remove project + data
```

## Multiple Projects

Just run `./setup.sh` again for each repo/Linear project. Each gets:
- Its own container, named `symphony-<project-name>`
- Its own port (auto-assigned: 4000, 4001, 4002, ...)
- Its own workspace volume
- Its own auth (persisted in a home volume)
- Its own WORKFLOW.md

All completely isolated from each other.

---

## Authentication

Auth is handled via device login / browser flow — your existing subscriptions:

- **Codex**: `codex login --device-auth` inside the container (OpenAI subscription)
- **GitHub**: `gh auth login -p https -h github.com` inside the container (device flow)
- **Linear**: API key provided during setup (manual — no subscription login available)

Auth persists across container restarts via a named Docker volume for `/home/agent`.

To re-auth later:
```bash
./setup.sh --shell <name>
# then inside:
codex login --device-auth
gh auth login -p https -h github.com
```

---

## Persistence & Restarts

- **Workspaces** persist in a named volume (`symphony-<name>-workspaces`)
- **Auth** persists in a named volume (`symphony-<name>-home`)
- **Container** is set to `restart: unless-stopped`

After a machine reboot, Docker will auto-restart all running containers.
Symphony picks up where it left off — it polls Linear for active issues
and resumes work.

To manually restart:
```bash
./setup.sh --start <name>
```

---

## Resource Limits

Defaults: 1 CPU core, 2GB RAM per container.

Set during setup, or edit `docker/projects/<name>/.env`:
```
CPU_LIMIT=2
MEMORY_LIMIT=4g
```
Then restart: `./setup.sh --stop <name> && ./setup.sh --start <name>`

---

## Project Directory Structure

```
docker/
├── setup.sh                    # Main setup & management script
├── Dockerfile                  # Multi-stage build
├── docker-compose.yml          # Alternative for single-project use
├── .env.example                # Reference env template
└── projects/
    ├── my-app/
    │   ├── .env                # Credentials + config
    │   └── workflow/
    │       └── WORKFLOW.md     # Project-specific workflow
    └── my-api/
        ├── .env
        └── workflow/
            └── WORKFLOW.md
```

---

## Troubleshooting

**Container exits immediately**
→ `./setup.sh --logs <name>` — usually WORKFLOW.md malformed or Linear key wrong.

**Auth expired**
→ `./setup.sh --shell <name>`, then `codex login` / `gh auth login`.

**Need to update Symphony**
→ `git pull upstream main && docker build -t symphony -f docker/Dockerfile . && ./setup.sh --stop <name> && ./setup.sh --start <name>`

**Want to reset a project completely**
→ `./setup.sh --remove <name>` then `./setup.sh` to recreate.
