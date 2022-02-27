defmodule Sally.Datapoint do
  @moduledoc """
  Database schema definition and functions for Datapoints associated to `Sally.DevAlias`
  """

  use Ecto.Schema
  require Logger
  import Ecto.Query, only: [from: 2, preload: 2, where: 3]

  schema "datapoint" do
    field(:temp_c, :float)
    field(:relhum, :float)
    field(:reading_at, :utc_datetime_usec)

    belongs_to(:dev_alias, Sally.DevAlias)
  end

  @returned [returning: true]
  @shift_opts [:years, :months, :days, :hours, :minutes, :seconds, :milliseconds]

  def add([_ | _] = aliases, raw_data, at), do: Enum.map(aliases, &add(&1, raw_data, at))

  def add(%Sally.DevAlias{} = a, raw_data, %DateTime{} = at) when is_map(raw_data) do
    raw_data
    |> Map.take([:temp_c, :relhum])
    |> Map.put(:reading_at, at)
    |> changeset(Ecto.build_assoc(a, :datapoints))
    |> Sally.Repo.insert!(@returned)
  end

  def changeset(changes, %__MODULE__{} = dp) when is_map(changes), do: changeset(dp, changes)

  @cast_columns [:temp_c, :relhum, :reading_at]
  @required_columns [:temp_c, :reading_at, :dev_alias_id]
  @validate_temp_c [greater_than: -30.0, less_than: 80.0]
  @validate_relhum [greater_than: 0.0, less_than_or_equal_to: 100.0]
  def changeset(%__MODULE__{} = dp, changes) when is_map(changes) do
    dp
    |> Ecto.Changeset.cast(changes, @cast_columns)
    |> Ecto.Changeset.validate_required(@required_columns)
    |> Ecto.Changeset.validate_number(:temp_c, @validate_temp_c)
    |> Ecto.Changeset.validate_number(:relhum, @validate_relhum)
  end

  @cleanup_defaults [days: -1]
  def cleanup(%Sally.DevAlias{} = dev_alias, opts) do
    ids = cleanup(:query, dev_alias, opts) |> Sally.Repo.all()

    purge(ids, opts)
  end

  def cleanup(:query, %{id: dev_alias_id}, opts) do
    shift_opts = Keyword.take(opts, @shift_opts)

    shift_opts = if shift_opts == [], do: @cleanup_defaults, else: shift_opts

    before_dt = Timex.now() |> Timex.shift(shift_opts)

    from(dap in __MODULE__,
      where: dap.dev_alias_id == ^dev_alias_id,
      where: dap.reading_at <= ^before_dt,
      order_by: :id,
      select: dap.id
    )
  end

  @shift_units [:months, :days, :hours, :minutes, :seconds, :milliseconds]
  def ids_query(opts) do
    query = from(dap in __MODULE__, order_by: :id, select: dap.id)

    Enum.reduce(opts, query, fn
      {:dev_alias_id, id}, query ->
        where(query, [dap], dap.dev_alias_id == ^id)

      {unit, _val} = shift_tuple, query when unit in @shift_units ->
        before = Timex.now() |> Timex.shift([shift_tuple])
        where(query, [dap], dap.reading_at <= ^before)

      kv, _query ->
        raise("unknown opt: #{inspect(kv)}")
    end)
  end

  def purge([], _opts), do: 0

  def purge([id | _] = ids, opts) when is_integer(id) do
    batch_size = opts[:batch_size] || 10

    batches = Enum.chunk_every(ids, batch_size)

    Enum.reduce(batches, 0, fn batch, total ->
      {purged, _} = from(x in __MODULE__, where: x.id in ^batch) |> Sally.Repo.delete_all()

      purged + total
    end)
  end

  # def purge(%Sally.DevAlias{datapoints: datapoints}, :all, batch_size \\ 10) do
  #   all_ids = Enum.map(datapoints, fn %{id: id} -> id end)
  #   batches = Enum.chunk_every(all_ids, batch_size)
  #
  #   for batch <- batches, reduce: {:ok, 0} do
  #     {:ok, acc} ->
  #       q = from(dp in __MODULE__, where: dp.id in ^batch)
  #
  #       {deleted, _} = Sally.Repo.delete_all(q)
  #
  #       {:ok, acc + deleted}
  #   end
  # end

  def status(name, opts) do
    status_query(name, opts) |> Sally.Repo.one()
  end

  @since_ms_default 1000 * 60 * 1
  @temp_f ~s|((avg(?) * 1.8) + 32.0)|
  def status_base_query(val, opts) when is_list(opts) do
    since_ms = Keyword.get(opts, :since_ms, @since_ms_default)
    field = if(is_binary(val), do: :name, else: :id)

    from(dev_alias in Sally.DevAlias,
      as: :dev_alias,
      where: field(dev_alias, ^field) == ^val,
      group_by: [:id],
      inner_lateral_join:
        latest in subquery(
          from(d in Sally.Datapoint,
            where: [dev_alias_id: parent_as(:dev_alias).id],
            where: d.reading_at >= ago(^since_ms, "millisecond")
          )
        ),
      select_merge: %{
        nature: :datapoints,
        seen_at: dev_alias.updated_at,
        status: %{
          points: count(latest.id),
          relhum: avg(latest.relhum),
          temp_c: avg(latest.temp_c),
          temp_f: fragment(@temp_f, latest.temp_c),
          first_at: min(latest.reading_at)
        }
      }
    )
  end

  def status_query(<<_::binary>> = name, opts) when is_list(opts) do
    query = status_base_query(name, opts)

    Enum.reduce(opts, query, fn
      {:preload, :device_and_host}, query ->
        query |> preload(device: :host)

      # query
      # |> join(:inner, [dev_alias], device in assoc(dev_alias, :device))
      # |> join(:inner, [_, _, device], host in assoc(device, :host))
      # |> preload([_, _, device, host], device: {device, host: host})

      _, query ->
        query
    end)
  end

  def summary(:keys), do: [:points, :relhum, :temp_c, :temp_f]

  def temp_f(%{temp_c: tc}), do: tc * 1.8 + 32.0
  def temp_f(_), do: nil

  # NOTE: assume the caller (Sally.Immutable.Dispatch has verified the map)
  def write(%{aliases: []}), do: []

  @measurement "immutables"
  @fields_want [:temp_c, :relhum]
  def write_metrics(%{aliases: aliases, datapoints: datapoints} = map) do
    Enum.map(datapoints, fn %{dev_alias_id: id} = dap ->
      %{name: name} = Enum.find(aliases, &match?(%{id: ^id}, &1))

      fields = Map.take(dap, @fields_want)
      fields_extra = %{temp_f: temp_f(dap), read_us: map.data.metrics["read"]}

      metric_opts = [
        measurement: @measurement,
        tags: [name: name, family: map.device.family],
        fields: Map.merge(fields, fields_extra)
      ]

      {:ok, _points} = Betty.metric(metric_opts)

      {name, :ok}
    end)
  end
end
