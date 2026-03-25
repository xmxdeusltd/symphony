defmodule SymphonyElixir.AgentAdapter do
  @moduledoc """
  Behaviour defining the interface for pluggable coding agent backends.

  Each adapter wraps a specific agent (e.g. Codex) and exposes a uniform
  session lifecycle: start_session -> run_turn(s) -> stop_session.
  """

  @type session :: map()
  @type turn_result :: {:ok, map()} | {:error, term()}

  @callback start_session(Path.t(), keyword()) :: {:ok, session()} | {:error, term()}
  @callback run_turn(session(), String.t(), map(), keyword()) :: turn_result()
  @callback stop_session(session()) :: :ok
  @callback normalize_update(map()) :: map()
end
