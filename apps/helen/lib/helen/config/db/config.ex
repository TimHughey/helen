defmodule Helen.Module.DB.Config do
  @moduledoc """
    Helen Module Config database implementation and functionality
  """
  use Timex
  use Ecto.Schema

  alias Helen.Module.DB.Config, as: Schema

  schema "helen_mod_config" do
    field(:module, :string)
    field(:description, :string, default: "<none>")
    field(:opts, :string)
    field(:version, Ecto.UUID)

    timestamps(type: :utc_datetime_usec)
  end

  ##
  ## Public API
  ##

  @doc false
  def all do
    for %Schema{module: m, opts: o} <- Repo.all(Schema), into: %{} do
      {opts, _} = Code.eval_string(o)

      {binary_to_mod(m), opts}
    end
  end

  @doc """
  Get the opts for modules that are like the specified pattern.
  """
  @doc since: "0.0.27"
  def begin_with(pattern) when is_atom(pattern) do
    import Ecto.Query, only: [from: 2]

    like_string = [mod_as_binary(pattern), "%"] |> IO.iodata_to_binary()

    from(x in Schema,
      where: like(x.module, ^like_string),
      order_by: x.module,
      select: x.module
    )
    |> Repo.all()
  end

  @doc false
  def create_or_update(mod, opts, description) do
    opts_binary =
      case opts do
        # turn the opts list into a binary to store in the db
        opts when is_list(opts) -> Enum.into(opts, []) |> inspect()
        opts when is_binary(opts) -> opts
      end

    upsert_opts = [
      module: mod_as_binary(mod),
      description: description,
      opts: opts_binary
    ]

    case upsert(%Schema{}, upsert_opts) do
      {:ok, %Schema{module: mod}} -> {:ok, binary_to_mod(mod)}
      error -> error
    end
  end

  @doc false
  def delete(mod) do
    with %Schema{} = x <- find(mod),
         {:ok, %Schema{}} <- Repo.delete(x) do
      :ok
    else
      rc -> rc
    end
  end

  @doc false
  def eval_opts(mod, overrides) when is_list(overrides) do
    import DeepMerge, only: [deep_merge: 2]

    with %Schema{opts: opts, version: vsn} <- find(mod),
         # NOTE: accepting risk of evaling string because it is coming
         #       from the database
         {val, _} <- Code.eval_string(opts),
         # apply any overrides
         opts <- deep_merge(val, overrides) do
      [opts, __available__: true, __version__: vsn] |> List.flatten()
    else
      _anything -> [overrides, __available__: false] |> List.flatten()
    end
  end

  @doc false
  def find(module_or_id) do
    check_args = fn
      x when is_binary(x) -> [module: module_or_id]
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
  def opts(module_or_id, overrides) do
    eval_opts(module_or_id, overrides)
  end

  @doc """
    Returned a parsed representation of a text configuration.
  """
  @doc since: "0.0.27"
  def parsed(module_or_id) do
    alias Helen.Config.Parser

    with %Schema{opts: raw, version: vsn} <- find(module_or_id),
         %{parser: %{syntax: :ok}} = config <- Parser.parse(raw) do
      put_in(config, [:__available__], true) |> put_in([:__version__], vsn)
    else
      _config -> put_in(%{}, [:__available__], false)
    end
  end

  @doc """
    Put the opts of a Module Config
  """
  @doc since: "0.0.26"
  def put(module_or_id, opts) when is_list(opts) do
    with %Schema{} = x <- find(module_or_id),
         opts_binary <- inspect(opts),
         {:ok, %Schema{opts: opts}} <- upsert(x, opts: opts_binary),
         {val, _} <- Code.eval_string(opts) do
      {:ok, val}
    else
      nil -> create_or_update(module_or_id, opts, "auto generated")
      rc -> rc
    end
  end

  ##
  ## PRIVATE
  ##

  defp upsert(%Schema{} = x, params) do
    {p, _} = Keyword.split(params, [:module, :opts, :description])

    on_conflict = {:replace_all_except, [:id, :module]}

    cs = changeset(x, p)

    case {:cs_valid, cs.valid?()} do
      {:cs_valid, true} ->
        # the keys on_conflict: and conflict_target: indicate the insert
        # is an "upsert"
        Repo.insert(cs,
          on_conflict: on_conflict,
          returning: true,
          conflict_target: [:module]
        )

      {:cs_valid, rc} ->
        {:failed, rc}
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

  defp binary_to_mod(x) do
    String.split(x, ".") |> Module.concat()
  end
end