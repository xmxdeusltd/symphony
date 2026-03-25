defmodule SymphonyElixir.RepoSupervisor do
  @moduledoc "Per-repo supervisor: owns one WorkflowStore + one Orchestrator."
  use Supervisor

  def start_link(%{name: name, workflow: workflow_path}) do
    Supervisor.start_link(__MODULE__, %{name: name, workflow: workflow_path},
      name: :"conductor_repo_sup_#{name}")
  end

  @impl true
  def init(%{name: name, workflow: workflow_path}) do
    ws_name = :"conductor_workflow_#{name}"
    orch_name = :"conductor_orchestrator_#{name}"

    children = [
      {SymphonyElixir.WorkflowStore, [name: ws_name, workflow_path: workflow_path]},
      {SymphonyElixir.Orchestrator, [name: orch_name, workflow_store: ws_name, repo_name: name]}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
