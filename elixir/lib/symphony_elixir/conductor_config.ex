defmodule SymphonyElixir.ConductorConfig do
  @moduledoc "Parser for conductor.yaml — multi-repo configuration."

  @spec load(Path.t()) :: {:ok, [map()]} | {:error, term()}
  def load(path) do
    with {:ok, content} <- File.read(path),
         {:ok, yaml} <- YamlElixir.read_from_string(content) do
      repos = Map.get(yaml, "repos", [])
      {:ok, Enum.map(repos, &normalize_repo/1)}
    end
  end

  defp normalize_repo(repo) when is_map(repo) do
    %{
      name: Map.fetch!(repo, "name"),
      workflow: Map.fetch!(repo, "workflow")
    }
  end
end
