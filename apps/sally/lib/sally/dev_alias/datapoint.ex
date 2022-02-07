defmodule Sally.Datapoint do
  @moduledoc """
  Database schema definition and functions for Datapoints associated to `Sally.DevAlias`
  """

  use Ecto.Schema
  require Logger
  import Ecto.Query, only: [from: 2]

  schema "datapoint" do
    field(:temp_c, :float)
    field(:relhum, :float)
    field(:reading_at, :utc_datetime_usec)

    belongs_to(:dev_alias, Sally.DevAlias)
  end

  @returned [returning: true]

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

  def purge(%Sally.DevAlias{datapoints: datapoints}, :all, batch_size \\ 10) do
    all_ids = Enum.map(datapoints, fn %{id: id} -> id end)
    batches = Enum.chunk_every(all_ids, batch_size)

    for batch <- batches, reduce: {:ok, 0} do
      {:ok, acc} ->
        q = from(dp in __MODULE__, where: dp.id in ^batch)

        {deleted, _} = Sally.Repo.delete_all(q)

        {:ok, acc + deleted}
    end
  end

  def status(name, opts) do
    status_query(name, opts) |> Sally.Repo.one()
  end

  @since_ms_default 1000 * 60 * 5
  @temp_f ~s|((avg(?) * 1.8) + 32.0)|
  def status_query(<<_::binary>> = name, opts) when is_list(opts) do
    since_ms = Keyword.get(opts, :since_ms, @since_ms_default)

    from(dev_alias in Sally.DevAlias,
      as: :dev_alias,
      where: [name: ^name],
      inner_lateral_join:
        latest in subquery(
          from(d in Sally.Datapoint,
            where: [dev_alias_id: parent_as(:dev_alias).id],
            where: d.reading_at >= ago(^since_ms, "millisecond")
          )
        ),
      group_by: [:id],
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

  def temp_f(%{temp_c: tc}), do: tc * 1.8 + 32.0
  def temp_f(_), do: nil

  # NOTE: assume the caller (Sally.Immutable.Dispatch has verified the map)
  def write(%{aliases: []}), do: []

  @measurement "immutables"
  @fields_want [:temp_c, :relhum]
  def write_metrics(%{aliases: aliases, datapoints: datapoints} = map) do
    family = map.device.family
    read_us = map.data.metrics["read"]

    Enum.map(datapoints, fn dap ->
      %{name: name} = Enum.find(aliases, fn dev_alias -> dev_alias.id == dap.dev_alias_id end)

      tags = [nqme: name, family: family]
      fields = Map.take(dap, @fields_want) |> Map.merge(%{temp_f: temp_f(dap), read_us: read_us})

      Betty.metric(@measurement, fields, tags)

      {name, :ok}
    end)
  end
end
