defmodule SymphonyElixir.MultiRepoSupervisor do
  @moduledoc "DynamicSupervisor managing per-repo orchestrator groups."
  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_repo(%{name: name, workflow: workflow_path}) do
    expanded = Path.expand(workflow_path)
    child_spec = %{
      id: :"conductor_repo_#{name}",
      start: {SymphonyElixir.RepoSupervisor, :start_link, [%{name: name, workflow: expanded}]},
      type: :supervisor,
      restart: :permanent
    }
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  def stop_repo(name) do
    case find_child_pid(name) do
      {:ok, pid} -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      :error -> {:error, :not_found}
    end
  end

  def list_repos do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
    |> Enum.filter(&is_pid/1)
  end

  defp find_child_pid(name) do
    target = :"conductor_repo_sup_#{name}"
    case Process.whereis(target) do
      pid when is_pid(pid) -> {:ok, pid}
      nil -> :error
    end
  end
end
