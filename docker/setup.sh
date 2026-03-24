#!/usr/bin/env bash
set -euo pipefail

# ── Symphony Project Setup ──────────────────────────────────────────
# Interactive setup script to configure and spawn a Symphony container
# for a specific repo + Linear project.
#
# Usage:
#   ./setup.sh                  # interactive setup
#   ./setup.sh --list           # list running symphony containers
#   ./setup.sh --stop <name>    # stop a project
#   ./setup.sh --stop-all       # stop all symphony containers
#   ./setup.sh --start <name>   # restart a stopped project
#   ./setup.sh --logs <name>    # tail logs for a project
#   ./setup.sh --shell <name>   # shell into a project container
#   ./setup.sh --remove <name>  # remove a project and its data

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECTS_DIR="${SCRIPT_DIR}/projects"
DOCKER_CONTEXT="$(dirname "${SCRIPT_DIR}")"

# ── Helpers ──────────────────────────────────────────────────────────

bold()  { printf "\033[1m%s\033[0m" "$*"; }
green() { printf "\033[32m%s\033[0m" "$*"; }
yellow(){ printf "\033[33m%s\033[0m" "$*"; }
red()   { printf "\033[31m%s\033[0m" "$*"; }
dim()   { printf "\033[2m%s\033[0m" "$*"; }

info()  { echo "$(green "›") $*"; }
warn()  { echo "$(yellow "⚠") $*"; }
err()   { echo "$(red "✗") $*" >&2; }
die()   { err "$@"; exit 1; }

ask() {
  local prompt="$1" default="${2:-}"
  if [[ -n "$default" ]]; then
    printf "$(bold "$prompt") $(dim "[$default]"): "
  else
    printf "$(bold "$prompt"): "
  fi
  read -r answer
  echo "${answer:-$default}"
}

ask_yn() {
  local prompt="$1" default="${2:-y}"
  local yn
  yn=$(ask "$prompt (y/n)" "$default")
  [[ "$yn" =~ ^[Yy] ]]
}

# Find next available port starting from 4000
next_port() {
  local port=4000
  while true; do
    if ! docker ps --format '{{.Ports}}' 2>/dev/null | grep -q "0.0.0.0:${port}->"; then
      # Also check if any project config already claims this port
      local claimed=false
      if [[ -d "$PROJECTS_DIR" ]]; then
        for env_file in "$PROJECTS_DIR"/*/".env" 2>/dev/null; do
          if [[ -f "$env_file" ]] && grep -q "SYMPHONY_PORT=${port}" "$env_file" 2>/dev/null; then
            claimed=true
            break
          fi
        done
      fi
      if ! $claimed; then
        echo "$port"
        return
      fi
    fi
    port=$((port + 1))
  done
}

container_name() {
  echo "symphony-${1}"
}

# ── Subcommands ──────────────────────────────────────────────────────

cmd_list() {
  echo
  bold "Symphony Projects"; echo
  echo "─────────────────────────────────────────────"
  
  if [[ ! -d "$PROJECTS_DIR" ]] || [[ -z "$(ls -A "$PROJECTS_DIR" 2>/dev/null)" ]]; then
    dim "  No projects configured. Run ./setup.sh to create one."; echo
    echo
    return
  fi

  for proj_dir in "$PROJECTS_DIR"/*/; do
    local name
    name=$(basename "$proj_dir")
    local cname
    cname=$(container_name "$name")
    local status="$(dim "not created")"
    
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${cname}$"; then
      if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${cname}$"; then
        status="$(green "running")"
      else
        status="$(yellow "stopped")"
      fi
    fi
    
    local port=""
    if [[ -f "${proj_dir}.env" ]]; then
      port=$(grep "^SYMPHONY_PORT=" "${proj_dir}.env" 2>/dev/null | cut -d= -f2 || true)
    fi
    
    printf "  %-24s %s" "$(bold "$name")" "$status"
    [[ -n "$port" ]] && printf "  $(dim "port %s")" "$port"
    echo
  done
  echo
}

cmd_stop() {
  local name="$1"
  local cname
  cname=$(container_name "$name")
  info "Stopping ${cname}..."
  docker stop "$cname" 2>/dev/null || warn "Container not running."
}

cmd_stop_all() {
  local containers
  containers=$(docker ps --filter "name=symphony-" --format '{{.Names}}' 2>/dev/null || true)
  if [[ -z "$containers" ]]; then
    info "No running symphony containers."
    return
  fi
  echo "$containers" | while read -r c; do
    info "Stopping $c..."
    docker stop "$c" 2>/dev/null || true
  done
  info "All stopped."
}

cmd_start() {
  local name="$1"
  local proj_dir="${PROJECTS_DIR}/${name}"
  [[ -d "$proj_dir" ]] || die "Project '${name}' not found in ${PROJECTS_DIR}/"
  
  local cname
  cname=$(container_name "$name")
  
  # Check if container exists but is stopped
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${cname}$"; then
    info "Starting existing container ${cname}..."
    docker start "$cname"
  else
    # Need to create and run
    info "Creating and starting ${cname}..."
    _run_project "$name"
  fi
  info "Started. Logs: ./setup.sh --logs ${name}"
}

cmd_logs() {
  local name="$1"
  docker logs -f "$(container_name "$name")" 2>&1
}

cmd_shell() {
  local name="$1"
  docker exec -it "$(container_name "$name")" bash
}

cmd_remove() {
  local name="$1"
  local cname
  cname=$(container_name "$name")
  
  if ask_yn "Remove project '${name}'? This stops the container and deletes project config" "n"; then
    docker rm -f "$cname" 2>/dev/null || true
    docker volume rm "${cname}-workspaces" 2>/dev/null || true
    docker volume rm "${cname}-home" 2>/dev/null || true
    rm -rf "${PROJECTS_DIR}/${name}"
    info "Removed project '${name}'."
  fi
}

# ── Build image (once) ───────────────────────────────────────────────

ensure_image() {
  local image_tag="symphony:latest"
  if docker image inspect "$image_tag" &>/dev/null; then
    return
  fi
  info "Building Symphony Docker image (first time only, this takes a few minutes)..."
  docker build -t "$image_tag" -f "${SCRIPT_DIR}/Dockerfile" "$DOCKER_CONTEXT"
  info "Image built."
}

# ── Run a project container ─────────────────────────────────────────

_run_project() {
  local name="$1"
  local proj_dir="${PROJECTS_DIR}/${name}"
  local cname
  cname=$(container_name "$name")
  
  # Source the .env
  set -a
  # shellcheck disable=SC1091
  source "${proj_dir}/.env"
  set +a
  
  local port="${SYMPHONY_PORT:-4000}"
  local cpu="${CPU_LIMIT:-1}"
  local mem="${MEMORY_LIMIT:-2g}"
  
  docker run -d \
    --name "$cname" \
    --restart unless-stopped \
    --cpus "$cpu" \
    --memory "$mem" \
    -e "LINEAR_API_KEY=${LINEAR_API_KEY}" \
    -e "OPENAI_API_KEY=${OPENAI_API_KEY:-}" \
    -p "${port}:4000" \
    -v "${proj_dir}/workflow:/workflow:ro" \
    -v "${cname}-workspaces:/workspaces" \
    -v "${cname}-home:/home/agent" \
    symphony:latest
}

# ── Interactive Setup ────────────────────────────────────────────────

cmd_setup() {
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bold "  Symphony Project Setup"; echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo

  # ── Step 1: Project name ───────────────────────────────────────
  info "Step 1: Project identity"
  echo
  local name
  name=$(ask "  Project name (lowercase, no spaces — used for container name)")
  name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
  [[ -z "$name" ]] && die "Project name cannot be empty."
  
  local proj_dir="${PROJECTS_DIR}/${name}"
  if [[ -d "$proj_dir" ]]; then
    if ask_yn "  Project '${name}' already exists. Reconfigure it?" "n"; then
      docker rm -f "$(container_name "$name")" 2>/dev/null || true
    else
      die "Aborted."
    fi
  fi

  echo

  # ── Step 2: Repository ─────────────────────────────────────────
  info "Step 2: Repository"
  echo
  local repo_url
  repo_url=$(ask "  Git clone URL (HTTPS or SSH)")
  [[ -z "$repo_url" ]] && die "Repo URL is required."
  
  # Extract org/repo for display
  local repo_short
  repo_short=$(echo "$repo_url" | sed 's|.*github.com[:/]||' | sed 's|\.git$||')

  echo

  # ── Step 3: Linear ─────────────────────────────────────────────
  info "Step 3: Linear project"
  echo
  echo "  $(dim "Get your project slug from the Linear project URL.")"
  echo "  $(dim "Example: for https://linear.app/myteam/project/my-project-abc123")"
  echo "  $(dim "the slug is: my-project-abc123")"
  echo
  local project_slug
  project_slug=$(ask "  Linear project slug")
  [[ -z "$project_slug" ]] && die "Project slug is required."
  
  local linear_key
  linear_key=$(ask "  Linear API key (Settings → Security → Personal API keys)")
  [[ -z "$linear_key" ]] && die "Linear API key is required."

  echo

  # ── Step 4: Auth ───────────────────────────────────────────────
  info "Step 4: Authentication"
  echo
  echo "  Codex and GitHub auth will be done interactively inside the"
  echo "  container using device login (your existing subscriptions)."
  echo
  echo "  $(dim "After setup completes, you'll be prompted to authenticate.")"

  echo

  # ── Step 5: Resources ─────────────────────────────────────────
  info "Step 5: Resources (optional)"
  echo
  local cpu mem
  cpu=$(ask "  CPU cores" "1")
  mem=$(ask "  Memory" "2g")

  echo

  # ── Generate configs ───────────────────────────────────────────
  info "Generating project files..."
  
  local port
  port=$(next_port)

  mkdir -p "${proj_dir}/workflow"

  # .env file
  cat > "${proj_dir}/.env" <<EOF
# Symphony project: ${name}
# Generated by setup.sh

LINEAR_API_KEY=${linear_key}
SYMPHONY_PORT=${port}
CPU_LIMIT=${cpu}
MEMORY_LIMIT=${mem}

# OpenAI auth is handled via 'codex login' inside the container.
# Set this only if you prefer API key auth instead:
OPENAI_API_KEY=
EOF

  # WORKFLOW.md — minimal template
  cat > "${proj_dir}/workflow/WORKFLOW.md" <<WORKFLOW_EOF
---
tracker:
  kind: linear
  project_slug: "${project_slug}"
  active_states:
    - Todo
    - In Progress
    - Merging
    - Rework
    - Human Review
  terminal_states:
    - Closed
    - Cancelled
    - Canceled
    - Duplicate
    - Done
polling:
  interval_ms: 30000
workspace:
  root: /workspaces
hooks:
  after_create: |
    git clone --depth 1 ${repo_url} .
agent:
  max_concurrent_agents: 10
  max_turns: 20
codex:
  command: codex app-server
  approval_policy: never
  thread_sandbox: workspace-write
  turn_sandbox_policy:
    type: workspaceWrite
---

You are working on a Linear ticket \`{{ issue.identifier }}\`

{% if attempt %}
Continuation context:

- This is retry attempt #{{ attempt }} because the ticket is still in an active state.
- Resume from the current workspace state instead of restarting from scratch.
{% endif %}

Issue context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Current status: {{ issue.state }}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Instructions:
1. Work autonomously on the issue. Never ask a human to perform follow-up actions.
2. Only stop early for a true blocker (missing required auth/permissions/secrets).
3. Keep a single persistent workpad comment (\`## Codex Workpad\`) updated with progress.

Work only in the provided repository copy. Do not touch any other path.
WORKFLOW_EOF

  info "Project files created at ${proj_dir}/"

  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bold "  Pre-flight Checklist"; echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
  echo "  Before starting Symphony, make sure your repo is ready:"
  echo
  echo "  $(bold "1. Harness Engineering")"
  echo "     Your codebase should follow harness engineering practices."
  echo "     See: $(dim "https://openai.com/index/harness-engineering/")"
  echo
  echo "  $(bold "2. WORKFLOW.md in your repo (optional but recommended)")"
  echo "     A WORKFLOW.md has been generated at:"
  echo "     $(dim "${proj_dir}/workflow/WORKFLOW.md")"
  echo "     Review and customize it for your project."
  echo
  echo "  $(bold "3. Codex skills (optional)")"
  echo "     Copy the .codex/skills/ directory from the symphony repo"
  echo "     into your target repo for commit, push, pull, land, and"
  echo "     linear skills:"
  echo "     $(dim "cp -r $(dirname "$SCRIPT_DIR")/.codex/skills/ /path/to/${repo_short}/.codex/skills/")"
  echo
  echo "  $(bold "4. Linear workflow states")"
  echo "     Add these custom states in Linear (Team Settings → Workflow)"
  echo "     under the \"Started\" category:"
  echo "     $(dim "• Rework")"
  echo "     $(dim "• Human Review")"
  echo "     $(dim "• Merging")"
  echo

  if ! ask_yn "  Ready to build and start?" "y"; then
    echo
    info "Setup saved. Start later with: ./setup.sh --start ${name}"
    return
  fi

  echo

  # ── Build & run ────────────────────────────────────────────────
  ensure_image
  
  info "Starting container $(container_name "$name") on port ${port}..."
  _run_project "$name"
  
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bold "  Authentication"; echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
  echo "  Opening a shell in the container for auth setup..."
  echo
  echo "  Run these commands inside the container:"
  echo
  echo "    $(bold "1.") $(green "codex login")            # OpenAI auth (uses your subscription)"
  echo "    $(bold "2.") $(green "gh auth login")          # GitHub auth (device flow)"
  echo
  echo "  Then type $(bold "exit") to return here."
  echo

  docker exec -it "$(container_name "$name")" bash

  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bold "  Done!"; echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
  echo "  $(bold "Project:")     ${name}"
  echo "  $(bold "Repo:")        ${repo_short}"
  echo "  $(bold "Linear:")      ${project_slug}"
  echo "  $(bold "Container:")   $(container_name "$name")"
  echo "  $(bold "Dashboard:")   http://localhost:${port}"
  echo "  $(bold "Resources:")   ${cpu} CPU / ${mem} RAM"
  echo
  echo "  $(bold "Commands:")"
  echo "    ./setup.sh --list              # list all projects"
  echo "    ./setup.sh --logs ${name}      # tail logs"
  echo "    ./setup.sh --shell ${name}     # shell into container"
  echo "    ./setup.sh --stop ${name}      # stop"
  echo "    ./setup.sh --start ${name}     # start (picks up where it left off)"
  echo "    ./setup.sh --remove ${name}    # remove project + data"
  echo
  echo "  Auth and workspaces persist across restarts."
  echo "  Symphony will pick up where it left off when restarted."
  echo
}

# ── Main ─────────────────────────────────────────────────────────────

main() {
  mkdir -p "$PROJECTS_DIR"

  case "${1:-}" in
    --list|-l)
      cmd_list
      ;;
    --stop)
      [[ -z "${2:-}" ]] && die "Usage: $0 --stop <project-name>"
      cmd_stop "$2"
      ;;
    --stop-all)
      cmd_stop_all
      ;;
    --start)
      [[ -z "${2:-}" ]] && die "Usage: $0 --start <project-name>"
      ensure_image
      cmd_start "$2"
      ;;
    --logs)
      [[ -z "${2:-}" ]] && die "Usage: $0 --logs <project-name>"
      cmd_logs "$2"
      ;;
    --shell)
      [[ -z "${2:-}" ]] && die "Usage: $0 --shell <project-name>"
      cmd_shell "$2"
      ;;
    --remove)
      [[ -z "${2:-}" ]] && die "Usage: $0 --remove <project-name>"
      cmd_remove "$2"
      ;;
    --help|-h)
      echo "Usage: $0 [command]"
      echo
      echo "Commands:"
      echo "  (none)              Interactive setup for a new project"
      echo "  --list              List all configured projects and status"
      echo "  --start <name>     Start/restart a project"
      echo "  --stop <name>      Stop a project"
      echo "  --stop-all          Stop all symphony containers"
      echo "  --logs <name>      Tail logs for a project"
      echo "  --shell <name>     Shell into a project container"
      echo "  --remove <name>    Remove a project and its data"
      ;;
    "")
      cmd_setup
      ;;
    *)
      die "Unknown command: $1. Use --help for usage."
      ;;
  esac
}

main "$@"
