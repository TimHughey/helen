defmodule Sensor.DB.Device do
  @moduledoc """
  Database functionality for Sensor Device
  """

  use Ecto.Schema
  require Ecto.Query
  alias Ecto.Query

  alias Sensor.DB.Alias, as: Alias
  alias Sensor.DB.Device, as: Schema

  schema "sensor_device" do
    field(:device, :string)
    field(:host, :string)
    field(:dev_latency_us, :integer, default: 0)
    field(:last_seen_at, :utc_datetime_usec)

    has_many(:aliases, Alias)

    timestamps(type: :utc_datetime_usec)
  end

  @stale_default_ms 60_000

  def changeset(x, p) do
    alias Common.DB
    alias Ecto.Changeset

    x
    |> Changeset.cast(p, columns(:cast))
    |> Changeset.validate_required(columns(:required))
    |> Changeset.validate_format(:device, DB.name_regex())
    |> Changeset.validate_format(:host, DB.name_regex())
    |> Changeset.validate_number(:dev_latency_us, greater_than_or_equal_to: 0)
  end

  def columns(:all) do
    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
  end

  def columns(:cast), do: columns(:all)
  def columns(:required), do: columns_all(drop: [:inserted_at, :updated_at])
  def columns(:replace), do: columns_all(drop: [:device, :inserted_at])

  def columns_all(opts) when is_list(opts) do
    keep_set = MapSet.new(opts[:only] || columns(:all))
    drop_set = MapSet.new(opts[:drop] || columns(:all))

    MapSet.difference(keep_set, drop_set) |> MapSet.to_list()
  end

  # @doc """
  # Deletes devices that were last updated before UTC now shifted backward by opts.
  #
  # Returns a list of the deleted devices.
  #
  # ## Examples
  #
  #     iex> Sensor.DB.Device.delete_unavailable([days: 7])
  #     ["dead_device1", "dead_device2"]
  #
  # """
  # @doc since: "0.0.27"
  # def delete_unavailable(opts) do
  #   import Helen.Time.Helper, only: [utc_shift_past: 1, valid_duration_opts?: 1]
  #   import Ecto.Query, only: [from: 2]
  #   import Repo, only: [all: 1]
  #
  #   case valid_duration_opts?(opts) do
  #     true ->
  #       before = utc_shift_past(opts)
  #
  #       from(x in Schema, where: x.updated_at < ^before)
  #       |> all()
  #       |> delete()
  #
  #     false ->
  #       {:bad_args, opts}
  #   end
  # end
  #
  # defp delete(x) do
  #   for %Schema{id: id, device: dev_name} = dev when is_integer(id) <-
  #         [x] |> List.flatten() do
  #     case Repo.delete(dev, timeout: 5 * 60 * 1000) do
  #       {:ok, %Schema{device: deleted_name}} -> {:ok, deleted_name}
  #       rc -> {:failed, dev_name, rc}
  #     end
  #   end
  # end

  def devices_begin_with(pattern) when is_binary(pattern) do
    like_string = IO.iodata_to_binary([pattern, "%"])

    Query.from(x in Schema,
      where: like(x.device, ^like_string),
      order_by: x.device,
      select: x.device
    )
    |> Repo.all()
  end

  # (1 of 2) find with proper opts
  def find(opts) when is_list(opts) and opts != [] do
    case Repo.get_by(Schema, opts) do
      %Schema{} = x -> preload(x)
      x when is_nil(x) -> nil
    end
  end

  # (2 of 2) validate param and build opts for find/2
  def find(id_or_device) do
    case id_or_device do
      x when is_binary(x) -> find(device: x)
      x when is_integer(x) -> find(id: x)
      x -> {:bad_args, "must be binary or integer: #{inspect(x)}"}
    end
  end

  def find_check_stale(id_or_device, opts) do
    stale_ms = EasyTime.iso8601_duration_to_ms(opts[:device_stale_after]) || @stale_default_ms

    case find(id_or_device) do
      nil -> {:device, nil}
      %Schema{} = d -> stale_check(d, stale_ms)
    end
  end

  # (1 of 2) load aliases for a schema
  def load_aliases(%Schema{} = d) do
    Repo.preload(d, [:aliases])
  end

  # (2 of 2) handle use in a pipeline
  def load_aliases({rc, schema_or_error}) do
    case {rc, schema_or_error} do
      {:ok, %Schema{} = d} -> {:ok, load_aliases(d)}
      {rc, x} -> {rc, x}
    end
  end

  def preload(%Schema{} = x), do: Repo.preload(x, [:aliases])

  # (1 of 2) receive the inbound msg, grab the keys of interest
  def upsert(%{device: _, host: _} = msg) do
    want = [:device, :host, :dev_latency_us, :last_seen_at]

    p = Map.take(msg, want) |> Map.put_new(:last_seen_at, DateTime.utc_now())

    put_in(msg, [:device], upsert(%Schema{}, p)) |> Map.drop([:dev_latency_us])
  end

  # (2 of 2) perform the actual insert with conflict check (upsert)
  def upsert(%Schema{} = d, p) when is_map(p) do
    # assemble the opts for upsert
    # check for conflicts on :device
    # if there is a conflict only replace specified columns
    opts = [on_conflict: {:replace, columns(:replace)}, returning: true, conflict_target: [:device]]

    changeset(d, p) |> Repo.insert(opts) |> load_aliases()
  end

  defp stale_check(%Schema{last_seen_at: seen_at} = d, stale_ms) do
    stale_dt = DateTime.utc_now() |> DateTime.add(stale_ms * -1, :millisecond)

    case DateTime.compare(seen_at, stale_dt) do
      :lt -> {:device_stale, [device: d.device, stale_ms: stale_ms]}
      x when x in [:gt, :eq] -> {:device, d}
    end
  end

  # @doc """
  # Return a list of Devices that are not aliased (no Sensor Alias)
  # """
  # @doc since: "0.0.27"
  # def unaliased do
  #   import Repo, only: [all: 1, preload: 2]
  #   import Ecto.Query, only: [from: 2]
  #
  #   q =
  #     from(x in Schema,
  #       order_by: [desc: x.inserted_at]
  #     )
  #
  #   # need to wrap the Repo.all/1 in a list in case the limit is 1
  #   for dev <- all(q) do
  #     case preload(dev, [:_alias_]) do
  #       %Schema{_alias_: nil, device: d, inserted_at: at} -> [{d, at}]
  #       _no_alias -> []
  #     end
  #   end
  #   |> List.flatten()
  # end

  # @doc """
  # Selects devices that were last updated before UTC now shifted backward by opts.
  #
  # Returns a list of the devices.
  #
  # ## Examples
  #
  #     iex> Sensor.DB.Device.unavailable([days: 7])
  #     ["dead_device1", "dead_device2"]
  #
  # """
  # @doc since: "0.0.27"
  # def unavailable(opts) do
  #   import Helen.Time.Helper, only: [utc_shift_past: 1, valid_duration_opts?: 1]
  #   import Ecto.Query, only: [from: 2]
  #   import Repo, only: [all: 1]
  #
  #   case valid_duration_opts?(opts) do
  #     true ->
  #       before = utc_shift_past(opts)
  #       query = from(x in Schema, where: x.updated_at < ^before)
  #
  #       for %Schema{device: device, updated_at: last_update} <- all(query) do
  #         {device, last_update}
  #       end
  #
  #     false ->
  #       {:bad_args, opts}
  #   end
  # end
end
