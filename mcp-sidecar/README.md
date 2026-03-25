# Conductor MCP Sidecar

MCP server that exposes Conductor orchestrator controls to any MCP client
(Hermes, Claude Desktop, Cursor, etc.).

## How it Works

The sidecar talks to the Conductor Elixir process via its Phoenix HTTP API
(`/api/v1/state`, `/api/v1/refresh`, etc.) and exposes those as MCP tools
over stdio.

## Install

```bash
cd mcp-sidecar
uv venv .venv --python 3.11
source .venv/bin/activate
uv pip install -e .
```

## Run

```bash
conductor-mcp --base-url http://localhost:4000
```

## Use with Hermes

Add to `~/.hermes/config.yaml`:

```yaml
mcp_servers:
  conductor:
    command: "/path/to/conductor/mcp-sidecar/.venv/bin/conductor-mcp"
    args: ["--base-url", "http://localhost:4000"]
    timeout: 30
```

Then Hermes will have access to:
- `conductor_list_runs` — Active agent runs across all repos
- `conductor_get_run` — Details of a specific run
- `conductor_get_state` — Full orchestrator state snapshot
- `conductor_refresh` — Trigger immediate poll cycle
- `conductor_get_issue` — Issue details with workspace, tokens, events

## Use with Claude Desktop

Add to Claude Desktop's MCP config:

```json
{
  "mcpServers": {
    "conductor": {
      "command": "/path/to/conductor/mcp-sidecar/.venv/bin/conductor-mcp",
      "args": ["--base-url", "http://localhost:4000"]
    }
  }
}
```
