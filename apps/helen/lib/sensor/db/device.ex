defmodule Sensor.DB.Device do
  @moduledoc """
  Database functionality for Sensor Device
  """

  use Ecto.Schema

  alias Sensor.DB.DataPoint, as: DataPoint
  alias Sensor.DB.Device, as: Schema
  alias Sensor.DB.Alias, as: Alias

  schema "sensor_device" do
    field(:device, :string)
    field(:host, :string)
    field(:dev_latency_us, :integer, default: 0)
    field(:last_seen_at, :utc_datetime_usec)
    field(:discovered_at, :utc_datetime_usec)

    has_many(:datapoints, DataPoint)

    has_one(:_alias_, Alias, references: :id, foreign_key: :device_id)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(x, p) when is_map(p) or is_list(p) do
    import Ecto.Changeset,
      only: [
        cast: 3,
        validate_required: 2,
        validate_format: 3,
        validate_number: 3
      ]

    import Common.DB, only: [name_regex: 0]

    cast(x, Enum.into(p, %{}), keys(:cast))
    |> validate_required(keys(:required))
    |> validate_format(:device, name_regex())
    |> validate_format(:host, name_regex())
    |> validate_number(:dev_latency_us, greater_than_or_equal_to: 0)
  end

  @doc """
  Deletes devices that were last updated before UTC now shifted backward by opts.

  Returns a list of the deleted devices.

  ## Examples

      iex> Sensor.DB.Device.delete_unavailable([days: 7])
      ["dead_device1", "dead_device2"]

  """
  @doc since: "0.0.27"
  def delete_unavailable(opts) when is_list(opts) do
    import Helen.Time.Helper, only: [utc_shift_past: 1, valid_duration_opts?: 1]
    import Ecto.Query, only: [from: 2]
    import Repo, only: [all: 1]

    case valid_duration_opts?(opts) do
      true ->
        before = utc_shift_past(opts)

        from(x in Schema, where: x.updated_at < ^before)
        |> all()
        |> delete()

      false ->
        {:bad_args, opts}
    end
  end

  defp delete(x) do
    for %Schema{id: id, device: dev_name} = dev when is_integer(id) <-
          [x] |> List.flatten() do
      case Repo.delete(dev) do
        {:ok, %Schema{device: deleted_name}} -> {:ok, deleted_name}
        rc -> {:failed, dev_name, rc}
      end
    end
  end

  @doc """
    Retrieve sensor device names
  """

  @doc since: "0.0.19"
  def devices do
    import Ecto.Query, only: [from: 2]

    from(x in Schema, select: x.device, order_by: x.device) |> Repo.all()
  end

  @doc """
    Retrieve sensor device names that begin with a pattern
  """

  @doc since: "0.0.19"
  def devices_begin_with(pattern) when is_binary(pattern) do
    import Ecto.Query, only: [from: 2]

    like_string = [pattern, "%"] |> IO.iodata_to_binary()

    from(x in Schema,
      where: like(x.device, ^like_string),
      order_by: x.device,
      select: x.device
    )
    |> Repo.all()
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
      x when is_binary(x) -> [device: x]
      x when is_integer(x) -> [id: x]
      x -> {:bad_args, x}
    end

    import Repo, only: [get_by: 2, preload: 2]

    with opts when is_list(opts) <- check_args.(id_or_name),
         %Schema{} = found <- get_by(Schema, opts) |> preload([:_alias_]) do
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
      |> Map.drop([:__meta__, :_alias_, :id, :datapoints])
      |> Map.keys()
      |> List.flatten()

  def keys(:cast), do: keys(:all)

  # defp keys(:upsert), do: keys_drop(:all, [:id, :device])

  def keys(:replace),
    do:
      keys_drop(:all, [
        :device,
        :discovered_at,
        :inserted_at
      ])

  def keys(:required),
    do: keys_drop(:cast, [:updated_at, :inserted_at])

  defp keys_drop(base_keys, drop),
    do:
      MapSet.difference(MapSet.new(keys(base_keys)), MapSet.new(drop))
      |> MapSet.to_list()

  @doc """
  Loads datapoints for a device
  """
  @doc since: "0.0.16"
  def load_datapoints(%Schema{} = dev, opts) do
    import Ecto.Query, only: [from: 2]
    import Repo, only: [preload: 2]

    since = since(opts)

    q =
      from(dp in DataPoint,
        where: dp.reading_at >= ^since,
        order_by: [desc: dp.reading_at]
      )

    dev |> preload(datapoints: q) |> preload(:_alias_)
  end

  @doc """
  Reload a %Sensor.DB.Device{}
  """

  @doc since: "0.0.16"
  def reload(args) do
    import Repo, only: [get!: 2, preload: 2]

    case args do
      # results of a Repo function
      {:ok, %Schema{id: id}} -> get!(Schema, id) |> preload(:_alias_)
      # an existing struct
      %Schema{id: id} -> get!(Schema, id) |> preload(:_alias_)
      # something we can't handle
      id when is_integer(id) -> get!(Schema, id) |> preload(:_alias_)
      args -> {:error, args}
    end
  end

  @doc """
  Return a list of Devices that are not aliased (no Sensor Alias)
  """
  @doc since: "0.0.27"
  def unaliased do
    import Repo, only: [all: 1, preload: 2]
    import Ecto.Query, only: [from: 2]

    q =
      from(x in Schema,
        order_by: [desc: x.inserted_at]
      )

    # need to wrap the Repo.all/1 in a list in case the limit is 1
    for dev <- all(q) do
      with %Schema{_alias_: nil, device: d, inserted_at: at} <-
             preload(dev, [:_alias_]) do
        [{d, at}]
      else
        _no_alias -> []
      end
    end
    |> List.flatten()
  end

  @doc """
  Selects devices that were last updated before UTC now shifted backward by opts.

  Returns a list of the devices.

  ## Examples

      iex> Sensor.DB.Device.unavailable([days: 7])
      ["dead_device1", "dead_device2"]

  """
  @doc since: "0.0.27"
  def unavailable(opts) when is_list(opts) do
    import Helen.Time.Helper, only: [utc_shift_past: 1, valid_duration_opts?: 1]
    import Ecto.Query, only: [from: 2]
    import Repo, only: [all: 1]

    case valid_duration_opts?(opts) do
      true ->
        before = utc_shift_past(opts)
        query = from(x in Schema, where: x.updated_at < ^before)

        for %Schema{device: device, updated_at: last_update} <- all(query) do
          {device, last_update}
        end

      false ->
        {:bad_args, opts}
    end
  end

  @doc """
  Upsert (insert or update) a Sensor.Schemas.Device

  input:
    message from an external source or or a map with necessary keys:
      %{device: string, host: string, dev_latency_us: integer, mtime: integer}

  returns input message populated with:
     device: the results of upsert/2
       {:ok, %Sensor.Schemas.Device{}}
       {:invalid_changes, %Changeset{}}
       {:error, actual error results from upsert/2}
  """

  @doc since: "0.0.15"
  def upsert(%{device: _, host: _, dev_latency_us: _, mtime: mtime} = msg) do
    import Helen.Time.Helper, only: [from_unix: 1, utc_now: 0]

    params = [:device, :host, :dev_latency_us, :discovered_at, :last_seen_at]

    # create a map of defaults for keys that may not exist in the msg
    params_default = %{
      discovered_at: from_unix(mtime),
      last_seen_at: utc_now()
    }

    # assemble a map of changes
    # NOTE:  the second map passed to Map.merge/2 replaces duplicate keys
    #        in the first map.  in this case we want all available data from
    #        the message however if some isn't available we provide it via
    #        changes_default
    params = Map.merge(params_default, Map.take(msg, params))

    # assemble the return message with the results of upsert/2
    Map.put(msg, :device, upsert(%Schema{}, params))
  end

  def upsert(msg) when is_map(msg),
    do: Map.put(msg, :device, {:error, :badmsg})

  def upsert(%Schema{} = x, params) when is_map(params) or is_list(params) do
    import Repo, only: [preload: 2]

    # make certain the params are a map
    params = Enum.into(params, %{})

    # assemble the opts for upsert
    # check for conflicts on :device
    # if there is a conflict only replace keys(:replace)
    opts = [
      on_conflict: {:replace, keys(:replace)},
      returning: true,
      conflict_target: [:device]
    ]

    cs = changeset(x, params)

    with {cs, true} <- {cs, cs.valid?},
         {:ok, %Schema{id: _id} = dev} <- Repo.insert(cs, opts) do
      {:ok, dev |> preload(:_alias_)}
    else
      {cs, false} ->
        {:invalid_changes, cs}

      {:error, rc} ->
        {:error, rc}

      error ->
        {:error, error}
    end
  end

  def upsert(_x, params) do
    {:error, params}
  end

  defp since(opts) do
    import Helen.Time.Helper, only: [utc_shift_past: 1]

    possible_opts = Keyword.take(opts, [:since, :since_secs])

    case possible_opts do
      [{:since, val} | _tail] -> val
      [{:since_secs, val} | _tail] -> val * 1000
      _x -> "PT2M"
    end
    |> utc_shift_past()
  end
end