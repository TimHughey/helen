defmodule Helen.Worker.Config.DB.Config do
  @moduledoc false

  use Ecto.Schema

  alias Helen.Worker.Config.DB
  alias Helen.Worker.Config.DB.Config, as: Schema

  schema "worker_config" do
    field(:module, :string)
    field(:comment, :string)
    field(:version, :string)

    has_many(:lines, DB.Line)

    timestamps(type: :utc_datetime_usec)
  end

  @doc since: "0.0.28"
  def find(module, version \\ :latest) do
    import Ecto.Query, only: [from: 2]
    import Repo, only: [all: 1, preload: 2]

    opts = find_opts(module: module, version: version)
    q = from(x in Schema, where: ^opts, order_by: [desc: x.version], limit: 1)

    with {:opts, [_head | _tail]} <- {:opts, opts},
         # we'll always get a list with a single item regardless of if
         # the latest (first row when sorted desending, limit 2) or exact match
         # of module and version
         [%Schema{} = found] <- all(q) do
      found |> preload([:lines])
    else
      {:opts, []} -> {:bad_args, [module: module, version: version]}
      [] -> nil
      x -> {:error, x}
    end
  end

  @doc false
  def find_opts(opts) when is_list(opts) do
    import Enum, only: [join: 2]
    import List, only: [flatten: 1]
    import Module, only: [split: 1]

    for {key, val} <- opts, reduce: [] do
      acc ->
        [
          acc,
          cond do
            key == :module and is_binary(val) -> {key, val}
            key == :module and is_atom(val) -> {key, split(val) |> join(".")}
            key == :version and is_binary(val) -> {key, val}
            true -> []
          end
        ]
        |> flatten()
    end
  end
end
