# Conductor Architecture

*Auto-maintained. Last updated: 2026-03-25 (Phase 3 complete)*

---

## System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CONDUCTOR (Single BEAM VM)                       │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                  Application Supervisor                      │   │
│  │                  (one_for_one strategy)                       │   │
│  │                                                               │   │
│  │  ┌──────────┐ ┌────────────┐ ┌──────────┐ ┌──────────────┐  │   │
│  │  │ PubSub   │ │ Task.Sup   │ │ HTTP     │ │ Status       │  │   │
│  │  │          │ │ (workers)  │ │ Server   │ │ Dashboard    │  │   │
│  │  └──────────┘ └────────────┘ └──────────┘ └──────────────┘  │   │
│  │                                                               │   │
│  │  ┌───────────────┐  ┌───────────────────────────────────┐    │   │
│  │  │ WorkflowStore │  │      MultiRepoSupervisor          │    │   │
│  │  │ (singleton,   │  │      (DynamicSupervisor)           │    │   │
│  │  │  single-repo  │  │                                     │    │   │
│  │  │  mode)        │  │  ┌─────────────────────────────┐   │    │   │
│  │  └───────────────┘  │  │ RepoSupervisor "api-service"│   │    │   │
│  │                      │  │  ┌─────────────┐ ┌────────┐│   │    │   │
│  │  ┌───────────────┐  │  │  │WorkflowStore│ │Orchestr.││   │    │   │
│  │  │ Orchestrator  │  │  │  │ (named)     │ │(named)  ││   │    │   │
│  │  │ (singleton,   │  │  │  └─────────────┘ └────────┘│   │    │   │
│  │  │  single-repo  │  │  └─────────────────────────────┘   │    │   │
│  │  │  mode)        │  │                                     │    │   │
│  │  └───────────────┘  │  ┌─────────────────────────────┐   │    │   │
│  │                      │  │ RepoSupervisor "frontend"   │   │    │   │
│  │                      │  │  ┌─────────────┐ ┌────────┐│   │    │   │
│  │                      │  │  │WorkflowStore│ │Orchestr.││   │    │   │
│  │                      │  │  │ (named)     │ │(named)  ││   │    │   │
│  │                      │  │  └─────────────┘ └────────┘│   │    │   │
│  │                      │  └─────────────────────────────┘   │    │   │
│  │                      └───────────────────────────────────┘    │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    Phoenix Endpoints                          │   │
│  │  GET  /              — LiveView Dashboard                     │   │
│  │  GET  /api/v1/state  — JSON state dump                        │   │
│  │  (future) /mcp       — MCP server (Phase 4)                   │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

**Two modes:**
- **Single-repo mode** (backward compat): Singleton WorkflowStore + Orchestrator.
  Activated by: `symphony WORKFLOW.md`
- **Multi-repo mode**: MultiRepoSupervisor spawns per-repo process pairs.
  Activated by: `symphony --conductor-config conductor.yaml`

Both can coexist — the singleton handles one repo, MultiRepoSupervisor handles additional repos.

---

## Orchestration Flow

```
                        ┌──────────────┐
                        │   Linear API  │
                        └──────┬───────┘
                               │ poll every N ms
                               ▼
                    ┌──────────────────────┐
                    │    Orchestrator      │
                    │    (GenServer)        │
                    │                      │
                    │  State:              │
                    │    running: %{}      │
                    │    retry_queue: %{}  │
                    │    agent_totals: %{} │
                    │    workflow_store: …  │
                    │    repo_name: …      │
                    └──────────┬───────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
              ▼                ▼                ▼
        ┌──────────┐    ┌──────────┐    ┌──────────┐
        │ Filter   │    │ Dispatch │    │Reconcile │
        │ eligible │    │ new work │    │ terminal │
        │ issues   │    │          │    │ issues   │
        └──────────┘    └─────┬────┘    └──────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  AgentRunner     │
                    │  (spawned Task)  │
                    └────────┬─────────┘
                             │
                    ┌────────┴────────┐
                    │                 │
                    ▼                 ▼
            ┌──────────────┐  ┌──────────────┐
            │ Workspace    │  │ Adapter      │
            │ .create()    │  │ .start()     │
            │ .run_hooks() │  │ .run_turn()  │
            └──────────────┘  │ .stop()      │
                              └──────────────┘
```

### Poll Cycle Detail

```
:tick
  │
  ├─ Process.put(:conductor_workflow_store, state.workflow_store)
  │  (ensures Config.settings!() returns this repo's config)
  │
  ├─ refresh_runtime_config(state)
  │
  ├─ Tracker.fetch_active_issues()
  │    │
  │    └─ Filter: not already running, not in retry cooldown,
  │       concurrency < max, state in active_states
  │
  ├─ For each eligible issue:
  │    │
  │    └─ Task.Supervisor.async_nolink(fn ->
  │         Process.put(:conductor_workflow_store, workflow_store)
  │         AgentRunner.run(issue, self(), opts)
  │       end)
  │
  ├─ Reconcile: stop agents for issues moved to terminal states
  │
  ├─ Stall detection: kill agents with no activity > stall_timeout_ms
  │
  └─ Schedule next :tick
```

---

## Agent Adapter Layer

```
                    ┌─────────────────────┐
                    │   AgentAdapter      │
                    │   (behaviour)        │
                    │                     │
                    │  start_session/2    │
                    │  run_turn/4         │
                    │  stop_session/1     │
                    │  normalize_update/1 │
                    └─────────┬───────────┘
                              │
                 ┌────────────┼────────────┐
                 │                         │
                 ▼                         ▼
    ┌────────────────────┐    ┌────────────────────┐
    │   CodexAdapter     │    │   HermesAdapter    │
    │   (default)        │    │                    │
    │                    │    │                    │
    │  Wraps AppServer   │    │  Spawns            │
    │  JSON-RPC 2.0      │    │  hermes chat -q    │
    │  over stdio        │    │  per turn          │
    │                    │    │                    │
    │  Persistent Port   │    │  Stateless between │
    │  across turns      │    │  turns, resumes    │
    │                    │    │  via --resume <id>  │
    └────────────────────┘    └────────────────────┘

    Protocol:                  Protocol:
    initialize                 hermes chat -q "prompt"
    thread/start                 -Q --yolo
    turn/start                   --resume <session_id>
    turn/* events                --provider/--model
    turn/completed               --skills/--toolsets
                               stdout → parse session_id
```

### Agent Turn Lifecycle

```
AgentRunner.run(issue, orchestrator_pid, opts)
  │
  ├─ adapter = Config.agent_adapter()
  │   ├─ agent.kind == "codex"  → CodexAdapter
  │   └─ agent.kind == "hermes" → HermesAdapter
  │
  ├─ adapter.start_session(workspace, opts)
  │   ├─ Codex:  Opens Port, JSON-RPC initialize + thread/start
  │   └─ Hermes: Stores config (no process spawned yet)
  │
  ├─ Loop (up to max_turns):
  │   │
  │   ├─ prompt = PromptBuilder.build_prompt(issue, opts)
  │   │
  │   ├─ adapter.run_turn(session, prompt, issue, opts)
  │   │   ├─ Codex:  turn/start → stream events → turn/completed
  │   │   └─ Hermes: spawn process → capture stdout → parse session_id
  │   │
  │   ├─ on_message callback → {:agent_worker_update, issue_id, msg}
  │   │   → Orchestrator updates running entry metrics
  │   │
  │   ├─ Update session (thread session_id for Hermes)
  │   │   session = Map.merge(session, Map.take(result, [:session_id]))
  │   │
  │   ├─ Check: is issue still in active state?
  │   │   ├─ Yes + turns remaining → continue loop
  │   │   ├─ Yes + max turns reached → return :ok (orchestrator retries)
  │   │   └─ No (terminal/moved) → return :ok (done)
  │   │
  │   └─ (loop)
  │
  └─ adapter.stop_session(session)
      ├─ Codex:  Close Port
      └─ Hermes: noop (process already exited)
```

---

## Config Resolution

```
Config.settings!() called
  │
  ├─ Check Process.get(:conductor_workflow_store)
  │   │
  │   ├─ nil (single-repo mode):
  │   │   └─ Workflow.current()
  │   │       └─ WorkflowStore (singleton, __MODULE__)
  │   │           └─ Reads from Application.get_env(:workflow_file_path)
  │   │
  │   └─ :"conductor_workflow_<name>" (multi-repo mode):
  │       └─ WorkflowStore.current(store_name)
  │           └─ Named GenServer reads its own WORKFLOW.md path
  │
  └─ Schema.parse(config) → typed settings struct
```

### WORKFLOW.md Config Schema

```yaml
---
tracker:
  kind: linear
  project_slug: my-project
  active_states: [Todo, In Progress, Rework]
  terminal_states: [Done, Cancelled]

polling:
  interval_ms: 5000

workspace:
  root: ~/conductor-workspaces

agent:
  kind: codex              # codex | hermes
  max_concurrent_agents: 5
  max_turns: 20
  # Hermes-specific (ignored when kind: codex)
  hermes_provider: anthropic
  hermes_model: claude-sonnet-4
  hermes_skills: [commit, push, linear]
  hermes_toolsets: terminal,file,web

codex:                      # Codex-specific settings
  command: codex app-server
  approval_policy: never
  thread_sandbox: danger-full-access
  turn_sandbox_policy:
    type: dangerFullAccess
    networkAccess: true

hooks:
  after_create: |
    git clone --depth 1 {repo_url} .
---

{Jinja2 prompt template}
```

### conductor.yaml (Multi-Repo)

```yaml
repos:
  - name: api-service
    workflow: ./workflows/api-service.md
  - name: frontend
    workflow: ./workflows/frontend.md
  - name: infra
    workflow: ./workflows/infra.md
```

---

## File Structure

```
conductor/
├── NOTICE                          # Apache 2.0 attribution (OpenAI Symphony)
├── LICENSE                         # Apache 2.0
├── README.md                       # Conductor docs
├── SPEC.md                         # Symphony specification (upstream)
├── .hermes/
│   ├── plans/                      # (gitignored) local planning docs
│   └── skills/                     # Agent-agnostic Hermes skills
│       ├── commit/SKILL.md
│       ├── push/SKILL.md
│       ├── pull/SKILL.md
│       ├── land/SKILL.md
│       ├── linear/SKILL.md
│       └── review/SKILL.md
├── .codex/
│   └── skills/                     # Codex-specific skills (upstream)
│       ├── commit/SKILL.md
│       ├── push/SKILL.md
│       ├── pull/SKILL.md
│       ├── land/SKILL.md
│       ├── linear/SKILL.md
│       └── debug/SKILL.md
├── docker/                         # Docker deployment (Phase 5)
│   ├── Dockerfile
│   ├── setup.sh
│   └── skills-generic/
├── elixir/
│   ├── mix.exs
│   ├── lib/
│   │   ├── symphony_elixir.ex                 # Application + supervision tree
│   │   └── symphony_elixir/
│   │       ├── agent_adapter.ex               # ★ Behaviour (Phase 1)
│   │       ├── agent_runner.ex                # ★ Refactored (Phase 1+2)
│   │       ├── agents/
│   │       │   ├── codex_adapter.ex           # ★ Codex wrapper (Phase 1)
│   │       │   ├── hermes_adapter.ex          # ★ Hermes CLI driver (Phase 2)
│   │       │   └── codex/
│   │       │       ├── app_server.ex          # Codex JSON-RPC (moved Phase 1)
│   │       │       └── dynamic_tool.ex        # Codex tool injection (moved Phase 1)
│   │       ├── conductor_config.ex            # ★ conductor.yaml parser (Phase 3)
│   │       ├── multi_repo_supervisor.ex       # ★ DynamicSupervisor (Phase 3)
│   │       ├── repo_supervisor.ex             # ★ Per-repo supervisor (Phase 3)
│   │       ├── config.ex                      # ★ Process-dict aware (Phase 1+3)
│   │       ├── config/
│   │       │   └── schema.ex                  # ★ agent.kind + hermes fields (Phase 2)
│   │       ├── orchestrator.ex                # ★ agent_* fields + multi-repo (Phase 1+3)
│   │       ├── workflow_store.ex              # ★ Named instances (Phase 3)
│   │       ├── workspace.ex                   # Workspace lifecycle
│   │       ├── prompt_builder.ex              # Issue → prompt rendering
│   │       ├── tracker.ex                     # Tracker abstraction
│   │       ├── tracker/
│   │       │   └── ...                        # Linear adapter
│   │       ├── cli.ex                         # ★ --conductor-config (Phase 3)
│   │       ├── status_dashboard.ex            # ★ Generic metrics (Phase 1)
│   │       ├── http_server.ex                 # Phoenix server
│   │       └── ...
│   ├── lib/symphony_elixir_web/
│   │   ├── presenter.ex                       # ★ agent_* fields (Phase 2)
│   │   ├── live/dashboard_live.ex             # ★ agent_totals (Phase 2)
│   │   └── ...
│   └── test/
│       └── symphony_elixir/
│           ├── hermes_adapter_test.exs        # ★ 17 tests (Phase 2)
│           └── ...                            # Existing tests (all passing)
```

★ = Modified or created by Conductor (Phases 1–3)

---

## Future Architecture (Phase 4+)

```
┌──────────────────────────────────────────────────────┐
│                  CONDUCTOR                            │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │  Elixir BEAM (Orchestration)                    │  │
│  │  Orchestrator(s) + WorkflowStore(s) + Dashboard │  │
│  │           │                                     │  │
│  │           │ HTTP /api/v1/state                   │  │
│  │           ▼                                     │  │
│  │  ┌──────────────────┐                           │  │
│  │  │  Phoenix HTTP API │◄── JSON ──┐              │  │
│  │  └──────────────────┘            │              │  │
│  └──────────────────────────────────┼──────────────┘  │
│                                     │                 │
│  ┌──────────────────────────────────┼──────────────┐  │
│  │  Python Sidecar (MCP Server)     │              │  │
│  │                                  │              │  │
│  │  Reads state from Phoenix API ───┘              │  │
│  │  Exposes MCP tools:                             │  │
│  │    conductor_list_repos                          │  │
│  │    conductor_list_runs                           │  │
│  │    conductor_dispatch                            │  │
│  │    conductor_stop_run                            │  │
│  │    conductor_pause_repo                          │  │
│  │    conductor_set_agent                           │  │
│  │                     │                            │  │
│  │                     │ MCP (stdio or HTTP)        │  │
│  └─────────────────────┼──────────────────────────┘  │
│                        │                              │
└────────────────────────┼──────────────────────────────┘
                         │
                         ▼
                  ┌──────────────┐
                  │  MCP Client  │
                  │  (Hermes,    │
                  │   Claude     │
                  │   Desktop,   │
                  │   Cursor)    │
                  └──────────────┘
```
