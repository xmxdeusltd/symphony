defmodule SymphonyElixir.HermesAdapterTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agents.HermesAdapter
  alias SymphonyElixir.Config

  # ── Test 1: Unit tests (no external deps) ──────────────────────────

  describe "start_session/2" do
    test "returns session map with all config fields" do
      hermes_config = %{
        provider: "anthropic",
        model: "claude-sonnet-4",
        skills: ["commit", "push"],
        toolsets: "terminal,file,web",
        stall_timeout_ms: 120_000
      }

      assert {:ok, session} =
               HermesAdapter.start_session("/tmp/test-workspace",
                 worker_host: nil,
                 hermes_config: hermes_config
               )

      assert session.workspace == "/tmp/test-workspace"
      assert session.session_id == nil
      assert session.provider == "anthropic"
      assert session.model == "claude-sonnet-4"
      assert session.skills == ["commit", "push"]
      assert session.toolsets == "terminal,file,web"
      assert session.stall_timeout_ms == 120_000
    end

    test "applies defaults when hermes_config is empty" do
      assert {:ok, session} = HermesAdapter.start_session("/tmp/test-workspace")

      assert session.workspace == "/tmp/test-workspace"
      assert session.session_id == nil
      assert session.provider == nil
      assert session.model == nil
      assert session.skills == []
      assert session.toolsets == "terminal,file"
      assert session.stall_timeout_ms == 300_000
    end
  end

  describe "stop_session/1" do
    test "returns :ok for any session" do
      assert :ok = HermesAdapter.stop_session(%{workspace: "/tmp/x", session_id: "abc"})
    end
  end

  describe "normalize_update/1" do
    test "passes through event and timestamp" do
      update = %{event: "turn/completed", timestamp: 1234567890, text: "hello"}
      result = HermesAdapter.normalize_update(update)
      assert result.event == "turn/completed"
      assert result.timestamp == 1234567890
      assert result.text == "hello"
    end

    test "fills defaults for missing keys" do
      result = HermesAdapter.normalize_update(%{})
      assert result.event == "agent_update"
      assert is_integer(result.timestamp)
      assert result.text == ""
    end
  end

  describe "session_id parsing" do
    # parse_session_id is private, so we test it through run_turn behavior.
    # But we can test the regex pattern directly here.

    test "extracts session_id from typical Hermes -Q output" do
      output = "╭─ ⚕ Hermes ─────╮\nPONG\n\nsession_id: 20260325_032812_1e3098"
      assert extract_session_id(output) == "20260325_032812_1e3098"
    end

    test "extracts session_id with extra whitespace" do
      output = "result text\n\nsession_id:    spaced_id   \n"
      assert extract_session_id(output) == "spaced_id"
    end

    test "returns nil when no session_id present" do
      output = "some output without session info"
      assert extract_session_id(output) == nil
    end

    test "handles session_id at end of output without trailing newline" do
      output = "OK\n\nsession_id: abc123"
      assert extract_session_id(output) == "abc123"
    end

    # Helper that mirrors HermesAdapter's private parse_session_id/1
    defp extract_session_id(output) do
      case Regex.run(~r/session_id:\s*(\S+)/, output) do
        [_, session_id] -> String.trim(session_id)
        _ -> nil
      end
    end
  end

  describe "CLI arg construction" do
    # Test the arg building logic by reconstructing it here.
    # This validates the adapter would construct correct commands.

    test "basic args without resume" do
      session = %{
        session_id: nil,
        provider: nil,
        model: nil,
        skills: [],
        toolsets: "terminal,file"
      }

      args = build_test_args(session, "do something")
      assert "-q" in args
      assert "-Q" in args
      assert "--yolo" in args
      assert "--toolsets" in args
      assert "terminal,file" in args
      refute "--resume" in args
      refute "--provider" in args
      refute "--model" in args
      refute "--skills" in args
    end

    test "args with resume session_id" do
      session = %{
        session_id: "20260325_040528_c335c5",
        provider: nil,
        model: nil,
        skills: [],
        toolsets: "terminal,file"
      }

      args = build_test_args(session, "continue")
      assert "--resume" in args
      assert "20260325_040528_c335c5" in args
    end

    test "args with provider, model, and skills" do
      session = %{
        session_id: nil,
        provider: "anthropic",
        model: "claude-sonnet-4",
        skills: ["commit", "push", "linear"],
        toolsets: "terminal,file,web"
      }

      args = build_test_args(session, "do work")
      assert "--provider" in args
      assert "anthropic" in args
      assert "--model" in args
      assert "claude-sonnet-4" in args
      assert "--skills" in args
      assert "commit,push,linear" in args
    end

    # Mirror of HermesAdapter's private build_args/2
    defp build_test_args(session, prompt) do
      args = ["-q", escape_prompt(prompt), "-Q", "--yolo"]

      args =
        if session.session_id,
          do: args ++ ["--resume", session.session_id],
          else: args

      args =
        if session.provider,
          do: args ++ ["--provider", session.provider],
          else: args

      args =
        if session.model,
          do: args ++ ["--model", session.model],
          else: args

      args =
        if session.skills != [],
          do: args ++ ["--skills", Enum.join(session.skills, ",")],
          else: args

      args =
        if session.toolsets,
          do: args ++ ["--toolsets", session.toolsets],
          else: args

      args
    end

    defp escape_prompt(prompt) do
      "'" <> String.replace(prompt, "'", "'\\''") <> "'"
    end
  end

  # ── Test 4: Config dispatch ─────────────────────────────────────────

  describe "Config.agent_adapter/0 dispatch" do
    test "returns CodexAdapter by default" do
      write_workflow_file!(Workflow.workflow_file_path(), [])
      assert Config.agent_adapter() == SymphonyElixir.Agents.CodexAdapter
    end

    test "returns HermesAdapter when agent.kind is hermes" do
      write_workflow_file!(Workflow.workflow_file_path(), agent_kind: "hermes")
      assert Config.agent_adapter() == SymphonyElixir.Agents.HermesAdapter
    end

    test "returns CodexAdapter when agent.kind is codex" do
      write_workflow_file!(Workflow.workflow_file_path(), agent_kind: "codex")
      assert Config.agent_adapter() == SymphonyElixir.Agents.CodexAdapter
    end
  end

  # ── Tests 2 & 3: Live Hermes tests (require hermes CLI) ────────────

  @live_hermes_skip_reason if(
                             System.get_env("SYMPHONY_RUN_LIVE_HERMES") != "1",
                             do:
                               "set SYMPHONY_RUN_LIVE_HERMES=1 to enable live Hermes adapter tests"
                           )

  describe "live: single turn" do
    @tag skip: @live_hermes_skip_reason
    @tag timeout: 60_000
    test "dispatches a prompt and parses session_id from output" do
      workspace = Path.join(System.tmp_dir!(), "hermes-adapter-test-#{System.unique_integer([:positive])}")
      File.mkdir_p!(workspace)

      try do
        {:ok, session} = HermesAdapter.start_session(workspace, hermes_config: %{})

        test_pid = self()

        result =
          HermesAdapter.run_turn(
            session,
            "Reply with just the word PONG. Nothing else.",
            %{id: "test-1", identifier: "TEST-1"},
            on_message: fn msg -> send(test_pid, {:got_update, msg}) end
          )

        assert {:ok, turn_result} = result
        assert is_binary(turn_result.session_id)
        assert turn_result.session_id =~ ~r/^\d{8}_\d{6}_[0-9a-f]+$/
        assert turn_result.output =~ "PONG"
        assert turn_result.exit_code == 0

        assert_receive {:got_update, %{event: "turn/completed"}}, 5_000
      after
        File.rm_rf(workspace)
      end
    end
  end

  describe "live: multi-turn session resume" do
    @tag skip: @live_hermes_skip_reason
    @tag timeout: 120_000
    test "second turn resumes context from first turn via --resume" do
      workspace = Path.join(System.tmp_dir!(), "hermes-adapter-resume-#{System.unique_integer([:positive])}")
      File.mkdir_p!(workspace)

      try do
        {:ok, session} = HermesAdapter.start_session(workspace, hermes_config: %{})

        # Turn 1: establish context
        {:ok, turn1} =
          HermesAdapter.run_turn(
            session,
            "Remember this secret code: BRAVO-9. Confirm you have it.",
            %{id: "test-resume", identifier: "TEST-R"},
            []
          )

        assert is_binary(turn1.session_id)

        # Update session with session_id (like agent_runner does)
        resumed_session = Map.put(session, :session_id, turn1.session_id)

        # Turn 2: verify context carried through
        {:ok, turn2} =
          HermesAdapter.run_turn(
            resumed_session,
            "What was the secret code I told you?",
            %{id: "test-resume", identifier: "TEST-R"},
            []
          )

        assert turn2.output =~ "BRAVO-9"
        # Session ID should be the same (resumed into same session)
        assert turn2.session_id == turn1.session_id
      after
        File.rm_rf(workspace)
      end
    end
  end
end
