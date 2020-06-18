defmodule Helen.DB.Module.Config do
  @moduledoc """
    Helen Module Config database implementation and functionality
  """
  use Timex
  use Ecto.Schema

  alias Helen.DB.Module.Config, as: Schema

  schema "helen_mod_config" do
    field(:module, :string)
    field(:description, :string, default: "<none>")
    field(:opts, :string)
    field(:version, Ecto.UUID)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Create a configuration entry for a specific mod

  Returns {:ok, "mod_as_string"} | {failed, term}

  ## Examples

    iex> Helen.DB.Module.Config.create_or_update(__MODULE__, [key: "value"], "description")
    {:ok, "Helen.DB.Module.Config"}

  Defaults for the opts (second parameter):
    [autostart: true, loop_timeout: [minutes: 1]]

  The second parameter is always merged into the default options.
  """
  @doc since: "0.0.26"
  def create_or_update(mod, opts \\ [], description \\ "<none>")
      when is_atom(mod) do
    # turn the opts list into a binary to store in the db
    opts_binary = Enum.into(opts, []) |> inspect()

    upsert_opts = [
      module: mod_as_binary(mod),
      description: description,
      opts: opts_binary
    ]

    with {:ok, %Schema{module: mod}} <- upsert(%Schema{}, upsert_opts) do
      {:ok, mod}
    else
      rc -> rc
    end
  end

  @doc """
  Return the evaluated opts for a Helen Module Configuration applying any
  passed overrides

  Returns Keyword.t() | [not_found: Atomt.t()]

  ## Examples

    iex> Helen.DB.Module.Config.eval_opts(__MODULE__, [autostart: false])
    [autostart: false, loop_timeout: [minutes: 1], config_available: true]
  """
  @doc since: "0.0.26"
  def eval_opts(mod, overrides \\ [])
      when is_atom(mod) and is_list(overrides) do
    with %Schema{opts: opts, version: vsn} <- find(mod),
         # NOTE: accepting risk of evaling string because it is coming
         #       from the database
         {val, _} <- Code.eval_string(opts),
         # apply any overrides
         opts <- Keyword.merge(val, overrides) do
      [opts, __available__: true, __version__: vsn] |> List.flatten()
    else
      _anything -> [overrides, __available__: false] |> List.flatten()
    end
  end

  @doc """
    Get a %Helen.DB.Module.Config{} by module or id

    Same return values as Repo.get_by/2

      1. nil if not found
      2. %Helen.DB.Module.Config{}

      ## Examples
        iex> Helen.DB.Module.Config.find(__MODULE__)
        %Config.DB.Config{}
  """

  @doc since: "0.0.26"
  def find(module_or_id) do
    check_args = fn
      x when is_atom(x) -> [module: mod_as_binary(module_or_id)]
      x when is_integer(x) -> [id: x]
      x -> {:bad_args, x}
    end

    import Repo, only: [get_by: 2]

    with opts when is_list(opts) <- check_args.(module_or_id),
         %Schema{} = found <- get_by(Schema, opts) do
      found
    else
      x when is_tuple(x) -> x
      x when is_nil(x) -> nil
      x -> {:error, x}
    end
  end

  @doc """
    Get the opts of a Module Config
  """
  @doc since: "0.0.26"
  def opts(module_or_id) do
    with %Schema{opts: opts} <- find(module_or_id),
         {val, _} <- Code.eval_string(opts) do
      val
    else
      rc -> rc
    end
  end

  @doc """
    Merge the opts of a Module Config
  """
  @doc since: "0.0.26"
  def opts_merge(module_or_id, opts) when is_list(opts) do
    with %Schema{opts: prev_opts_binary} = x <- find(module_or_id),
         {prev_opts, _} <- Code.eval_string(prev_opts_binary),
         opts_binary <- Keyword.merge(prev_opts, opts) |> inspect(),
         {:ok, %Schema{opts: new_opts_binary}} <- upsert(x, opts: opts_binary),
         {val, _} <- Code.eval_string(new_opts_binary) do
      {:ok, val}
    else
      rc -> rc
    end
  end

  @doc """
    Put the opts of a Module Config
  """
  @doc since: "0.0.26"
  def opts_put(module_or_id, opts) when is_list(opts) do
    with %Schema{} = x <- find(module_or_id),
         opts_binary <- inspect(opts),
         {:ok, %Schema{opts: opts}} <- upsert(x, opts: opts_binary),
         {val, _} <- Code.eval_string(opts) do
      {:ok, val}
    else
      rc -> rc
    end
  end

  defp upsert(%Schema{} = x, params) do
    {p, _} = Keyword.split(params, [:module, :opts, :description])

    on_conflict = {:replace_all_except, [:id, :module]}

    cs = changeset(x, p)

    with {:cs_valid, true} <- {:cs_valid, cs.valid?()} do
      # the keys on_conflict: and conflict_target: indicate the insert
      # is an "upsert"
      Repo.insert(cs,
        on_conflict: on_conflict,
        returning: true,
        conflict_target: [:module]
      )
    else
      {:cs_valid, false} -> {:invalid_changes, cs}
      rc -> {:failed, rc}
    end
  end

  defp changeset(x, params) do
    import Ecto.Changeset,
      only: [cast: 3, validate_required: 2, unique_constraint: 3]

    import Ecto.UUID, only: [generate: 0]

    # every insert or update gets a new version UUID
    p = Enum.into(params, %{version: generate()})

    cast(x, p, [:module, :description, :opts, :version])
    |> validate_required([:module, :opts, :version])
    |> unique_constraint(:module, [:module])
  end

  defp mod_as_binary(mod) do
    Atom.to_string(mod) |> Module.split() |> Enum.join(".")
  end
end
