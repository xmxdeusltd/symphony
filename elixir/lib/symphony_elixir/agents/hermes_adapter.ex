defmodule SymphonyElixir.Agents.HermesAdapter do
  @moduledoc """
  Agent adapter that spawns `hermes chat` as an Erlang Port per turn.

  Unlike CodexAdapter (which keeps a persistent Port open), HermesAdapter
  spawns a fresh process for each turn and threads the session_id through
  for multi-turn conversations via `--resume`.
  """

  @behaviour SymphonyElixir.AgentAdapter
  require Logger

  @impl true
  def start_session(workspace, opts \\ []) do
    # Hermes sessions are stateless between turns — no persistent process.
    # We store config and start with no session_id (set after first turn).
    hermes_config = Keyword.get(opts, :hermes_config, %{})

    {:ok,
     %{
       workspace: workspace,
       session_id: nil,
       worker_host: Keyword.get(opts, :worker_host),
       provider: Map.get(hermes_config, :provider),
       model: Map.get(hermes_config, :model),
       skills: Map.get(hermes_config, :skills, []),
       toolsets: Map.get(hermes_config, :toolsets, "terminal,file"),
       stall_timeout_ms: Map.get(hermes_config, :stall_timeout_ms, 300_000)
     }}
  end

  @impl true
  def run_turn(session, prompt, _issue, opts \\ []) do
    on_message = Keyword.get(opts, :on_message, fn _ -> :ok end)
    workspace = session.workspace

    # Build the hermes command
    args = build_args(session, prompt)

    Logger.info("Hermes adapter: launching hermes chat in #{workspace}")

    # Spawn hermes as a Port
    cmd = Enum.join(["hermes", "chat" | args], " ")

    port =
      Port.open({:spawn, cmd}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:cd, to_charlist(workspace)}
      ])

    # Collect output
    {output, exit_code} = collect_port_output(port, session.stall_timeout_ms)

    # Parse session_id from output (format: "session_id: <id>")
    session_id = parse_session_id(output) || session.session_id

    # Send update to orchestrator
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    on_message.(%{
      event: "turn/completed",
      timestamp: timestamp,
      text: output
    })

    case exit_code do
      0 ->
        {:ok,
         %{
           session_id: session_id,
           output: output,
           exit_code: 0
         }}

      code ->
        {:error, {:hermes_exit, code, output}}
    end
  end

  @impl true
  def stop_session(_session) do
    # Hermes spawns per turn — nothing to stop between turns
    :ok
  end

  @impl true
  def normalize_update(update) do
    # Hermes updates are simple text — wrap in standard format
    %{
      event: Map.get(update, :event, "agent_update"),
      timestamp:
        Map.get(update, :timestamp, DateTime.utc_now() |> DateTime.to_unix(:millisecond)),
      text: Map.get(update, :text, "")
    }
  end

  # --- Private ---

  defp build_args(session, prompt) do
    args = [
      "-q",
      escape_prompt(prompt),
      "-Q",
      "--yolo"
    ]

    # Add --resume if we have a session_id from a previous turn
    args =
      if session.session_id do
        args ++ ["--resume", session.session_id]
      else
        args
      end

    # Add provider/model if configured
    args =
      if session.provider do
        args ++ ["--provider", session.provider]
      else
        args
      end

    args =
      if session.model do
        args ++ ["--model", session.model]
      else
        args
      end

    # Add skills
    args =
      if session.skills != [] do
        args ++ ["--skills", Enum.join(session.skills, ",")]
      else
        args
      end

    # Add toolsets
    args =
      if session.toolsets do
        args ++ ["--toolsets", session.toolsets]
      else
        args
      end

    args
  end

  defp escape_prompt(prompt) do
    # Shell-escape the prompt for safe passing
    "'" <> String.replace(prompt, "'", "'\\''") <> "'"
  end

  defp collect_port_output(port, timeout_ms) do
    collect_port_output(port, timeout_ms, "")
  end

  defp collect_port_output(port, timeout_ms, acc) do
    receive do
      {^port, {:data, data}} ->
        collect_port_output(port, timeout_ms, acc <> data)

      {^port, {:exit_status, status}} ->
        {acc, status}
    after
      timeout_ms ->
        Port.close(port)
        Logger.warning("Hermes adapter: process timed out after #{timeout_ms}ms")
        {acc, 1}
    end
  end

  defp parse_session_id(output) do
    case Regex.run(~r/session_id:\s*(\S+)/, output) do
      [_, session_id] -> String.trim(session_id)
      _ -> nil
    end
  end
end
ELIXIR_EOF; __hermes_rc=$?; printf '__HERMES_FENCE_a9f7b3__'; exit $__hermes_rc
