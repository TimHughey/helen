defmodule Sensor.DB.Alias do
  @moduledoc """
  Database functionality for Sensor Alias
  """

  use Ecto.Schema

  alias Sensor.DB.Device
  alias Sensor.DB.Alias, as: Schema

  schema "sensor_alias" do
    field(:name, :string)
    field(:device_id, :integer)
    field(:description, :string, default: "<none>")
    field(:type, :string, default: "auto")
    field(:ttl_ms, :integer, default: 60_000)

    belongs_to(:device, Device,
      source: :device_id,
      references: :id,
      foreign_key: :device_id,
      define_field: false
    )

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(x, p) when is_map(p) do
    import Ecto.Changeset,
      only: [
        cast: 3,
        validate_required: 2,
        validate_format: 3,
        validate_number: 3
      ]

    import Common.DB, only: [name_regex: 0]

    cast(x, p, keys(:cast))
    |> validate_required(keys(:required))
    |> validate_format(:name, name_regex())
    |> validate_number(:ttl_ms, greater_than_or_equal_to: 0)
  end

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
  def find(id_or_name) do
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

  def keys(:all),
    do:
      Map.from_struct(%Schema{})
      |> Map.drop([:__meta__, :id, :device])
      |> Map.keys()
      |> List.flatten()

  def keys(:cast), do: keys(:all)

  # defp keys(:upsert), do: keys_drop(:all, [:id, :device])

  def keys(:replace),
    do: keys_drop(:all, [:name, :inserted_at])

  def keys(:update),
    do: keys_drop(:all, [:inserted_at])

  def keys(:required),
    do:
      keys_drop(:cast, [
        :description,
        :type,
        :ttl_ms,
        :updated_at,
        :inserted_at
      ])

  defp keys_drop(base_keys, drop),
    do:
      MapSet.difference(MapSet.new(keys(base_keys)), MapSet.new(drop))
      |> MapSet.to_list()

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

  @doc false
  def rename(%Schema{} = x, opts) when is_list(opts) do
    name = Keyword.get(opts, :name)

    changes =
      Keyword.take(opts, [
        :name,
        :description,
        :ttl_ms
      ])
      |> Enum.into(%{})

    with {:args, true} <- {:args, is_binary(name)},
         cs <- changeset(x, changes),
         {cs, true} <- {cs, cs.valid?},
         {:ok, sa} <- Repo.update(cs, returning: true) do
      {:ok, sa}
    else
      {:args, false} -> {:bad_args, opts}
      {%Ecto.Changeset{} = cs, false} -> {:invalid_changes, cs}
      error -> error
    end
  end

  @doc """
  Rename a Sensor alias

      Optional opts:
      description: <binary>   -- new description
      ttl_ms:      <integer>  -- new ttl_ms
  """
  @doc since: "0.0.23"
  def rename(name_or_id, name, opts \\ []) when is_list(opts) do
    # no need to guard name_or_id, find/1 handles it
    with %Schema{} = x <- find(name_or_id),
         {:ok, %Schema{name: n}} <- rename(x, name: name) do
      {:ok, n}
    else
      error -> error
    end
  end

  def update(%Schema{} = x, params, opts)
      when is_map(params) or is_list(params) do
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
    # make certain the params are a map
    params = Enum.into(params, %{})
    # assemble the opts for upsert
    # check for conflicts on :device
    # if there is a conflict only replace keys(:replace)
    opts = [
      on_conflict: {:replace, keys(:replace)},
      returning: true,
      conflict_target: [:name]
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
