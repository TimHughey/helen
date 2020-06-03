defmodule Remote.DB.Profile do
  @moduledoc """
  Database implementation for Remote Profile
  """

  require Logger

  alias Remote.Schemas.Profile, as: Schema

  @doc """
    Creates a new Remote Profile with specified name and optional parameters

      ## Examples
        iex> Remote.Schemas.Profile.create("default", dalsemi_enable: true,
            i2c_enable: true, pwm_enable: false)
            {:ok, }%Remote.Schemas.Profile{}}

            {:duplicate, name}

            {:error, anything}
  """
  @doc since: "0.0.8"
  def create(name, opts \\ []) when is_binary(name) and is_list(opts) do
    import Remote.Schemas.Profile, only: [changeset: 2, keys: 1]

    params =
      Keyword.take(opts, keys(:create_opts))
      |> Enum.into(%{})
      |> Map.merge(%{name: name})

    cs = changeset(%Schema{}, params)

    with {:cs_valid, true} <- {:cs_valid, cs.valid?()},
         {:ok, %Schema{id: id} = x} <-
           Repo.insert(cs,
             on_conflict: :nothing,
             returning: true,
             conflict_target: [:name]
           ),
         {:id_valid, true} <- {:id_valid, is_integer(id)} do
      {:ok, x}
    else
      {:id_valid, false} -> {:duplicate, name}
      catchall -> {:error, catchall}
    end
  end

  @doc """
    Duplicate an existing Remote Profile

    Ultimately calls create/2 so same return results

      ## Examples
        iex> Remote.Schemas.Profile.duplicate(name, copy_name)
        {:ok, %Remote.Schemas.Profile{}}

        {:not_found, name}
  """

  @doc since: "0.0.8"
  def duplicate(name, copy_name)
      when is_binary(name) and is_binary(copy_name) do
    import Remote.Schemas.Profile, only: [keys: 1]

    with {:find, %Schema{} = x} <- {:find, find(name)},
         source_map <- Map.from_struct(x) |> Map.take(keys(:create_opts)),
         description <- ["copy of", name] |> Enum.join(" "),
         source_map <- Map.put(source_map, :description, description),
         copy_opts <- Map.to_list(source_map) do
      create(copy_name, copy_opts)
    else
      {:find, nil} -> {:not_found, name}
      error -> {:error, error}
    end
  end

  @doc """
    Get a %Remote.Schemas.Profile{} by id or name

    Same return values as Repo.get_by/2

      1. nil if not found
      2. %Remote.Schemas.Profile{}

      ## Examples
        iex> Remote.Schemas.Profile.find("default")
        %Remote.Schemas.Profile{}
  """

  @doc since: "0.0.8"
  def find(id_or_name) when is_integer(id_or_name) or is_binary(id_or_name) do
    check_args = fn
      x when is_binary(x) -> [name: x]
      x when is_integer(x) -> [id: x]
      x -> {:bad_args, x}
    end

    import Repo, only: [get_by: 2, preload: 2]

    with opts when is_list(opts) <- check_args.(id_or_name),
         %Schema{} = found <- get_by(Schema, opts) do
      found
    else
      x when is_tuple(x) -> x
      x when is_nil(x) -> nil
      x -> {:error, x}
    end
  end

  def lookup_key(key) do
    import Remote.Schemas.Profile, only: [keys: 1]

    keys(:all)
    |> Enum.filter(fn x ->
      str = Atom.to_string(x)
      String.contains?(str, key)
    end)
  end

  @doc """
    Reload a previously loaded Remote.Schemas.Profile or get by id

    Leverages Repo.get!/2 and raises on failure

    ## Examples
      iex> Remote.Schemas.Profile.reload(1)
      %Remote.Schemas.Profile{}
  """

  @doc since: "0.0.8"
  def reload(opt) do
    handle_args = fn
      {:ok, %Schema{id: id}} -> id
      %Schema{id: id} -> id
      id when is_integer(id) -> id
      x -> x
    end

    import Repo, only: [get!: 2]

    with id when is_integer(id) <- handle_args.(opt) do
      get!(Schema, id)
    else
      x -> {:error, x}
    end
  end

  @doc """
    Retrieve Remote Profile Names

    ## Examples
      iex> Remote.Schemas.Profile.names()
      ["default"]
  """

  @doc since: "0.0.8"
  def names do
    import Ecto.Query, only: [from: 2]

    from(x in Schema, select: x.name, order_by: [:name]) |> Repo.all()
  end

  @doc """
  Lookup a Profile and convert to for external use
  """

  @doc since: "0.0.20"
  def to_external_map(name) do
    import Remote.Schemas.Profile, only: [external_map: 1]

    with %Schema{} = p <- find(name) do
      external_map(p)
    else
      _not_found -> %{}
    end
  end

  @doc """
    Updates an existing Remote Profile using the provided list of opts

    >
    > `:version` is updated when changeset contains changes.
    >

      ## Examples

        Update by profile name

        iex> Remote.Schemas.Profile.update("default", [i2c_enable: false])
        {:ok, %Remote.Schemas.Profile{}}

        Update by profile id

        iex> Remote.Schemas.Profile.update(12, [i2c_enable: false])
        {:ok, %Remote.Schemas.Profile{}}

        Update in a pipeline (e.g. Remote.Schemas.Profile.duplicate/2)

        iex> Remote.Schemas.Profile.update({:ok, %Remote.Schemas.Profile{}}, opts)
        {:ok, %Remote.Schemas.Profile{}}
  """

  @doc since: "0.0.8"
  def update(%Schema{id: id} = x, opts) when is_integer(id) and is_list(opts) do
    import Ecto.Changeset, only: [cast: 3]
    import Remote.Schemas.Profile, only: [changeset: 2, keys: 1]

    with {:bad_opts, []} <- {:bad_opts, Keyword.drop(opts, keys(:all))},
         cs <- changeset(x, opts),
         {:cs_valid, cs, true} <- {:cs_valid, cs, cs.valid?},
         {:changes, true} <- {:changes, map_size(cs.changes) > 0},
         cs <- cast(cs, %{version: Ecto.UUID.generate()}, [:version]),
         {:cs_valid, cs, true} <- {:cs_valid, cs, cs.valid?} do
      Repo.update(cs, returning: true)
    else
      {:bad_opts, u} -> {:unrecognized_opts, u}
      {:changes, false} -> {:no_changes, x}
      {:cs_valid, cs, false} -> {:invalid_changes, cs}
      error -> {:error, error}
    end
  end

  def update({:ok, %Schema{id: _} = x}, opts) when is_list(opts) do
    update(x, opts)
  end

  def update({rc, error}, _opts) do
    {rc, error}
  end

  def update(id_or_name, opts)
      when is_integer(id_or_name) or is_binary(id_or_name) do
    with {:ok, %Schema{name: name} = p} <- find(id_or_name) |> update(opts),
         res <- Map.take(p, Keyword.keys(opts)) |> Enum.to_list() do
      [name: name] ++ res
    else
      error -> error
    end
  end

  def update(catchall) do
    Logger.warn(["update/2 error: ", inspect(catchall, pretty: true)])
    {:error, catchall}
  end
end
