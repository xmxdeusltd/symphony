# Conductor

**Vendor-agnostic coding agent orchestrator.** Fork of [OpenAI Symphony](https://github.com/openai/symphony).

Conductor makes the coding agent pluggable — swap between Codex, Hermes, or future agents without changing the orchestrator. It polls your issue tracker, creates isolated workspaces, and dispatches the agent of your choice.

## What's Different from Symphony

| Feature | Symphony | Conductor |
|---------|----------|-----------|
| Coding agent | Codex only | Pluggable (Codex default, Hermes, extensible) |
| Agent config | `codex:` in WORKFLOW.md | `agent:` with `kind:` selector |
| Multi-repo | Single repo per instance | Multiple repos per instance (planned) |
| MCP server | No | Planned — any MCP client can control Conductor |
| Dashboard | Phoenix LiveView | Phoenix LiveView (generalized metrics) |

## Quick Start

Same as Symphony — see the [Symphony SPEC.md](SPEC.md) for full documentation.

```bash
cd elixir
mise trust && mise install
mise exec -- mix setup
mise exec -- mix build
mise exec -- ./bin/symphony /path/to/WORKFLOW.md --port 4000 \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails
```

### Using Hermes as the Agent

Set `agent.kind: hermes` in your WORKFLOW.md:

```yaml
---
agent:
  kind: hermes
  provider: anthropic
  model: claude-sonnet-4
  skills: [commit, push, linear]
  toolsets: terminal,file,web
  max_turns: 20
# ... rest of config
---
```

### Using Codex (Default)

Existing Symphony WORKFLOW.md files work unchanged:

```yaml
---
agent:
  kind: codex
  command: codex app-server
  approval_policy: never
  thread_sandbox: danger-full-access
# ... rest of config
---
```

Legacy `codex:` config key is also supported for backward compatibility.

## Architecture

The key abstraction is `AgentAdapter` — a behaviour that each agent backend implements:

```
Orchestrator → AgentAdapter.start_session()
             → AgentAdapter.run_turn()
             → AgentAdapter.stop_session()
```

See `lib/symphony_elixir/agent_adapter.ex` for the behaviour definition.

## License

Apache 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Original work Copyright 2025 OpenAI. Modifications by xmxdeusltd.
