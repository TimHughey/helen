defmodule Helen.Worker.Config.DB.Config do
  @moduledoc false

  use Ecto.Schema

  alias Helen.Worker.Config.DB.Config, as: Schema
  alias Helen.Worker.Config.DB.Line

  schema "worker_config" do
    field(:module, :string)
    field(:comment, :string)

    has_many(:lines, Line, foreign_key: :worker_config_id)

    timestamps(type: :utc_datetime_usec)
  end

  def as_binary(module, version) when version in [:latest, :previous] do
    cfgs = find(module)

    case Enum.at(cfgs, version_index(version), :not_found) do
      %Schema{lines: lines} -> Line.as_binary(lines)
      :not_found -> :not_found
    end
  end

  @doc false
  def changeset(cfg, params) do
    import Ecto.Changeset,
      only: [
        cast: 3,
        validate_required: 2
      ]

    cfg
    |> cast(Enum.into(params, %{}), [:module, :comment])
    |> validate_required([:module])
  end

  @doc """
  Find a Worker Configuration
  """
  @doc since: "0.0.28"
  def find(module) do
    import Ecto.Query, only: [from: 2]
    import Repo, only: [all: 1]

    opts = find_opts(module: module)

    if opts == [] do
      {:bad_args, module}
    else
      query =
        from(x in Schema, where: ^opts, order_by: [desc: x.updated_at], limit: 2)

      case all(query) do
        [] -> []
        x when is_list(x) -> Line.preload(x)
        x -> {:error, x}
      end
    end
  end

  @doc false
  def find_opts(opts) when is_list(opts) do
    import List, only: [flatten: 1]

    for {key, val} <- opts, reduce: [] do
      acc ->
        [
          acc,
          cond do
            key == :module and is_binary(val) -> {key, val}
            key == :module and is_atom(val) -> {key, module_to_binary(val)}
            true -> []
          end
        ]
        |> flatten()
    end
  end

  def insert(params) when is_map(params) or is_list(params) do
    insert(%Schema{}, params)
  end

  def insert(%Schema{} = x, params) when is_map(params) or is_list(params) do
    cs = changeset(x, params)

    with {cs, true} <- {cs, cs.valid?()},
         # the keys on_conflict: and conflict_target: indicate the insert
         # is an "upsert"
         {:ok, %Schema{id: _id} = x} <- Repo.insert(cs, returning: true) do
      {:ok, x |> Line.preload()}
    else
      {cs, false} ->
        {:invalid_changes, cs}

      {:error, rc} ->
        {:error, rc}

      error ->
        {:error, error}
    end
  end

  def module_to_binary(mod) do
    import Enum, only: [join: 2]
    import Module, only: [split: 1]

    case mod do
      x when is_atom(x) -> split(mod) |> join(".")
      x when is_binary(x) -> mod
    end
  end

  def version_index(:latest), do: 0
  def version_index(:previous), do: 1
end
