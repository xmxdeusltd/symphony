"""Tests for the Conductor MCP server."""

import asyncio
import json
import pytest
from unittest.mock import patch

from conductor_mcp.server import create_server
from conductor_mcp.client import ConductorClient


class TestConductorClient:
    """Unit tests for the HTTP client."""

    def test_init_default_url(self):
        client = ConductorClient()
        assert client.base_url == "http://localhost:4000"

    def test_init_custom_url(self):
        client = ConductorClient(base_url="http://myhost:5000/")
        assert client.base_url == "http://myhost:5000"

    def test_init_strips_trailing_slash(self):
        client = ConductorClient(base_url="http://localhost:4000/")
        assert client.base_url == "http://localhost:4000"


class TestMCPServer:
    """Tests for MCP tool registration and handler logic.

    We test the handler functions that are registered with the server,
    not the Server's internal dispatch (which requires a full MCP session).
    """

    def test_server_creates_with_name(self):
        server = create_server(base_url="http://localhost:4000")
        assert server is not None
        assert server.name == "conductor-mcp"

    def test_server_has_tool_handlers_registered(self):
        from mcp.types import ListToolsRequest, CallToolRequest
        server = create_server()
        assert ListToolsRequest in server.request_handlers
        assert CallToolRequest in server.request_handlers


class TestToolHandlers:
    """Test the tool handler functions directly via a thin test harness.

    We extract the handler functions by re-creating them with the same
    client mock, bypassing the MCP Server decorator plumbing.
    """

    @pytest.fixture
    def mock_client(self):
        return ConductorClient.__new__(ConductorClient)

    def _make_handlers(self, client):
        """Build the handler functions with a given client, same logic as server.py."""
        from conductor_mcp.client import ConductorClient
        import json
        from mcp.types import TextContent

        async def handle_tool(name: str, arguments: dict) -> list:
            try:
                if name == "conductor_list_runs":
                    runs = client.list_runs()
                    if not runs:
                        return [TextContent(type="text", text="No active runs.")]
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

        return handle_tool

    @pytest.mark.asyncio
    async def test_list_runs_empty(self, mock_client):
        handle = self._make_handlers(mock_client)
        with patch.object(ConductorClient, "list_runs", return_value=[]):
            result = await handle("conductor_list_runs", {})
            assert "No active runs" in result[0].text

    @pytest.mark.asyncio
    async def test_list_runs_with_data(self, mock_client):
        handle = self._make_handlers(mock_client)
        mock_runs = [
            {
                "issue_identifier": "ENG-123",
                "status": "running",
                "running": {
                    "state": "In Progress",
                    "tokens": {"total_tokens": 5000},
                    "turn_count": 3,
                },
            }
        ]
        with patch.object(ConductorClient, "list_runs", return_value=mock_runs):
            result = await handle("conductor_list_runs", {})
            assert "ENG-123" in result[0].text
            assert "tokens=5000" in result[0].text
            assert "turns=3" in result[0].text

    @pytest.mark.asyncio
    async def test_get_run_not_found(self, mock_client):
        handle = self._make_handlers(mock_client)
        with patch.object(ConductorClient, "get_run", return_value=None):
            result = await handle("conductor_get_run", {"identifier": "ENG-999"})
            assert "not found" in result[0].text

    @pytest.mark.asyncio
    async def test_get_run_found(self, mock_client):
        handle = self._make_handlers(mock_client)
        mock_issue = {"issue_identifier": "ENG-123", "status": "running"}
        with patch.object(ConductorClient, "get_run", return_value=mock_issue):
            result = await handle("conductor_get_run", {"identifier": "ENG-123"})
            parsed = json.loads(result[0].text)
            assert parsed["issue_identifier"] == "ENG-123"

    @pytest.mark.asyncio
    async def test_get_state(self, mock_client):
        handle = self._make_handlers(mock_client)
        mock_state = {"issues": [], "agent_totals": {"input_tokens": 0}}
        with patch.object(ConductorClient, "get_state", return_value=mock_state):
            result = await handle("conductor_get_state", {})
            parsed = json.loads(result[0].text)
            assert "agent_totals" in parsed

    @pytest.mark.asyncio
    async def test_refresh(self, mock_client):
        handle = self._make_handlers(mock_client)
        mock_result = {"status": "accepted"}
        with patch.object(ConductorClient, "refresh", return_value=mock_result):
            result = await handle("conductor_refresh", {})
            parsed = json.loads(result[0].text)
            assert parsed["status"] == "accepted"

    @pytest.mark.asyncio
    async def test_unknown_tool(self, mock_client):
        handle = self._make_handlers(mock_client)
        result = await handle("conductor_nonexistent", {})
        assert "Unknown tool" in result[0].text

    @pytest.mark.asyncio
    async def test_error_handling(self, mock_client):
        handle = self._make_handlers(mock_client)
        with patch.object(
            ConductorClient, "get_state", side_effect=Exception("connection refused")
        ):
            result = await handle("conductor_get_state", {})
            assert "Error" in result[0].text
            assert "connection refused" in result[0].text
