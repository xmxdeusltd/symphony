"""MCP server that exposes Conductor orchestrator tools."""

import argparse
import json
import sys

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

from conductor_mcp.client import ConductorClient


def create_server(base_url: str = "http://localhost:4000") -> Server:
    """Create and configure the MCP server with all conductor tools."""
    server = Server("conductor-mcp")
    client = ConductorClient(base_url=base_url)

    @server.list_tools()
    async def list_tools() -> list[Tool]:
        return [
            Tool(
                name="conductor_list_runs",
                description="List all active agent runs across repos. Shows issue identifier, status, agent type, tokens used, and duration.",
                inputSchema={
                    "type": "object",
                    "properties": {},
                },
            ),
            Tool(
                name="conductor_get_run",
                description="Get details of a specific agent run by issue identifier (e.g. ENG-123).",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "identifier": {
                            "type": "string",
                            "description": "Issue identifier (e.g. ENG-123)",
                        },
                    },
                    "required": ["identifier"],
                },
            ),
            Tool(
                name="conductor_get_state",
                description="Get the full orchestrator state snapshot — all running issues, totals, rate limits, and config.",
                inputSchema={
                    "type": "object",
                    "properties": {},
                },
            ),
            Tool(
                name="conductor_refresh",
                description="Trigger an immediate poll cycle — forces the orchestrator to check Linear for new issues right now instead of waiting for the next tick.",
                inputSchema={
                    "type": "object",
                    "properties": {},
                },
            ),
            Tool(
                name="conductor_get_issue",
                description="Get detailed status of a specific issue including workspace path, turn count, tokens, last event, and retry info.",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "identifier": {
                            "type": "string",
                            "description": "Issue identifier (e.g. ENG-123)",
                        },
                    },
                    "required": ["identifier"],
                },
            ),
        ]

    @server.call_tool()
    async def call_tool(name: str, arguments: dict) -> list[TextContent]:
        try:
            if name == "conductor_list_runs":
                runs = client.list_runs()
                if not runs:
                    return [TextContent(type="text", text="No active runs.")]
                # Format as a readable summary
                lines = []
                for run in runs:
                    issue_id = run.get("issue_identifier", "?")
                    status = run.get("status", "?")
                    running = run.get("running", {})
                    state = running.get("state", "?")
                    tokens = running.get("tokens", {})
                    total_tokens = tokens.get("total_tokens", 0)
                    turn_count = running.get("turn_count", 0)
                    lines.append(
                        f"{issue_id} | status={status} state={state} "
                        f"turns={turn_count} tokens={total_tokens}"
                    )
                return [TextContent(type="text", text="\n".join(lines))]

            elif name == "conductor_get_run":
                identifier = arguments.get("identifier", "")
                run = client.get_run(identifier)
                if run is None:
                    return [TextContent(type="text", text=f"Issue {identifier} not found.")]
                return [TextContent(type="text", text=json.dumps(run, indent=2))]

            elif name == "conductor_get_state":
                state = client.get_state()
                return [TextContent(type="text", text=json.dumps(state, indent=2))]

            elif name == "conductor_refresh":
                result = client.refresh()
                return [TextContent(type="text", text=json.dumps(result, indent=2))]

            elif name == "conductor_get_issue":
                identifier = arguments.get("identifier", "")
                issue = client.get_run(identifier)
                if issue is None:
                    return [TextContent(type="text", text=f"Issue {identifier} not found.")]
                return [TextContent(type="text", text=json.dumps(issue, indent=2))]

            else:
                return [TextContent(type="text", text=f"Unknown tool: {name}")]

        except Exception as e:
            return [TextContent(type="text", text=f"Error: {e}")]

    return server


async def run_server(base_url: str = "http://localhost:4000"):
    """Run the MCP server over stdio."""
    server = create_server(base_url=base_url)
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, server.create_initialization_options())


def main():
    parser = argparse.ArgumentParser(description="Conductor MCP sidecar server")
    parser.add_argument(
        "--base-url",
        default="http://localhost:4000",
        help="Conductor Elixir API base URL (default: http://localhost:4000)",
    )
    args = parser.parse_args()

    import asyncio
    asyncio.run(run_server(base_url=args.base_url))


if __name__ == "__main__":
    main()
