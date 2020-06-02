defmodule Sensor.DB.Alias do
  @moduledoc """
  Database functionality for Sensor Alias
  """

  alias Sensor.Schemas.Alias, as: Schema
  alias Sensor.Schemas.Device

  def create(%Device{id: id}, name, opts \\ [])
      when (is_binary(name) and is_list(opts)) or is_map(opts) do
    opts = Enum.into(opts, [])
    #
    # grab keys of interest for the schema (if they exist) and populate the
    # required parameters from the function call
    #
    params =
      Keyword.take(opts, [:description, :type, :ttl_ms])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.into(%{})
      |> Map.merge(%{device_id: id, name: name, device_checked: true})

    upsert(%Schema{}, params)
  end

  @doc """
    Get a sensor alias by id or name

    Same return values as Repo.get_by/2

      1. nil if not found
      2. %Sensor.Schemas.Alias{}

      ## Examples
        iex> Sensor.DB.Alias.find("default")
        %Sensor.Schemas.Alias{}
  """

  @doc since: "0.0.16"
  def find(id_or_name) when is_integer(id_or_name) or is_binary(id_or_name) do
    check_args = fn
      x when is_binary(x) -> [name: x]
      x when is_integer(x) -> [id: x]
      x -> {:bad_args, x}
    end

    import Repo, only: [get_by: 2, preload: 2]

    with opts when is_list(opts) <- check_args.(id_or_name),
         %Schema{} = found <- get_by(Schema, opts) |> preload([:device]) do
      found
    else
      x when is_tuple(x) -> x
      x when is_nil(x) -> nil
      x -> {:error, x}
    end
  end

  @doc """
    Retrieve sensor alias names
  """

  @doc since: "0.0.8"
  def names do
    import Ecto.Query, only: [from: 2]

    from(x in Schema, select: x.name, order_by: x.name) |> Repo.all()
  end

  @doc """
    Retrieve sensor alias names that begin with a pattern
  """

  @doc since: "0.0.19"
  def names_begin_with(pattern) when is_binary(pattern) do
    import Ecto.Query, only: [from: 2]

    like_string = [pattern, "%"] |> IO.iodata_to_binary()

    from(s in Schema,
      where: like(s.name, ^like_string),
      order_by: s.name,
      select: s.name
    )
    |> Repo.all()
  end

  @doc """
    Reload a previously loaded sensor alias

    Leverages Repo.get!/2 and raises on failure

    ## Examples
      iex> Sensor.DB.Alias.reload(1)
      %Sensor.Schemas.Alias{}
  """

  @doc since: "0.0.16"
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

  def update(%Schema{} = x, params, opts)
      when is_map(params) or is_list(params) do
    import Sensor.Schemas.Alias, only: [changeset: 2, keys: 1]

    # make certain the params are a map passed to changeset
    cs = changeset(x, Enum.into(params, %{}))

    with {cs, true} <- {cs, cs.valid?},
         {:ok, %Schema{id: _id} = x} <- Repo.update(cs, opts) do
      {:ok, x}
    else
      {cs, false} ->
        {:invalid_changes, cs}

      {:error, rc} ->
        {:error, rc}

      error ->
        {:error, error}
    end
  end

  def upsert(%Schema{} = x, params) when is_map(params) or is_list(params) do
    import Sensor.Schemas.Alias, only: [changeset: 2, keys: 1]

    # make certain the params are a map
    params = Enum.into(params, %{})
    # assemble the opts for upsert
    # check for conflicts on :device
    # if there is a conflict only replace keys(:replace)
    opts = [
      on_conflict: {:replace, keys(:replace)},
      returning: true,
      conflict_target: :name
    ]

    cs = changeset(x, params)

    with {cs, true} <- {cs, cs.valid?},
         {:ok, %Schema{id: _id} = x} <- Repo.insert(cs, opts) do
      {:ok, x}
    else
      {cs, false} ->
        {:invalid_changes, cs}

      {:error, rc} ->
        {:error, rc}

      error ->
        {:error, error}
    end
  end
end
