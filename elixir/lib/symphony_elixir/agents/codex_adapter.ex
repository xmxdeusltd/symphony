defmodule SymphonyElixir.Agents.CodexAdapter do
  @moduledoc """
  AgentAdapter implementation that delegates to the Codex app-server.
  """

  @behaviour SymphonyElixir.AgentAdapter

  alias SymphonyElixir.Agents.Codex.AppServer

  @impl true
  def start_session(workspace, opts \\ []) do
    AppServer.start_session(workspace, opts)
  end

  @impl true
  def run_turn(session, prompt, issue, opts \\ []) do
    AppServer.run_turn(session, prompt, issue, opts)
  end

  @impl true
  def stop_session(session) do
    AppServer.stop_session(session)
  end

  @impl true
  def normalize_update(update) do
    update
  end
end
