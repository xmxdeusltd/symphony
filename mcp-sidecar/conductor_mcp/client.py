"""HTTP client for the Conductor (Phoenix) API."""

import httpx
from typing import Optional


class ConductorClient:
    """Talks to the Conductor Elixir HTTP API."""

    def __init__(self, base_url: str = "http://localhost:4000"):
        self.base_url = base_url.rstrip("/")
        self._client = httpx.Client(timeout=30.0)

    def get_state(self) -> dict:
        """GET /api/v1/state — full orchestrator state snapshot."""
        resp = self._client.get(f"{self.base_url}/api/v1/state")
        resp.raise_for_status()
        return resp.json()

    def get_issue(self, identifier: str) -> dict:
        """GET /api/v1/:issue_identifier — single issue details."""
        resp = self._client.get(f"{self.base_url}/api/v1/{identifier}")
        resp.raise_for_status()
        return resp.json()

    def refresh(self) -> dict:
        """POST /api/v1/refresh — trigger an immediate poll cycle."""
        resp = self._client.post(f"{self.base_url}/api/v1/refresh")
        resp.raise_for_status()
        return resp.json()

    def list_runs(self) -> list[dict]:
        """Extract running issues from state snapshot."""
        state = self.get_state()
        return state.get("issues", [])

    def get_run(self, identifier: str) -> Optional[dict]:
        """Get details of a specific running issue."""
        try:
            return self.get_issue(identifier)
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 404:
                return None
            raise

    def close(self):
        self._client.close()
