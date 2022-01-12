defmodule Sally.Datapoint do
  @moduledoc """
  Database schema definition and functions for Datapoints associated to `Sally.DevAlias`
  """

  require Logger

  use Ecto.Schema
  require Ecto.Query
  alias Ecto.Query

  alias __MODULE__, as: Schema
  alias Sally.{DevAlias, Repo}

  schema "datapoint" do
    field(:temp_c, :float)
    field(:relhum, :float)
    field(:reading_at, :utc_datetime_usec)

    belongs_to(:dev_alias, DevAlias)
  end

  def add(repo, %DevAlias{} = a, raw_data, %DateTime{} = at) when is_map(raw_data) do
    raw_data
    |> Map.take([:temp_c, :relhum])
    |> Map.put(:reading_at, at)
    |> changeset(Ecto.build_assoc(a, :datapoints))
    |> repo.insert(returning: true)
  end

  def changeset(changes, %Schema{} = dp) when is_map(changes), do: changeset(dp, changes)

  def changeset(%Schema{} = dp, changes) when is_map(changes) do
    alias Ecto.Changeset

    dp
    |> Changeset.cast(changes, columns(:cast))
    |> Changeset.validate_required([:temp_c, :reading_at, :dev_alias_id])
    |> Changeset.validate_number(:temp_c, greater_than: -30.0, less_than: 80.0)
    |> Changeset.validate_number(:relhum, greater_than: 0.0, less_than_or_equal_to: 100.0)
  end

  def columns(:all) do
    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
  end

  def columns(:cast), do: columns(:all)

  @since_ms_default 1000 * 60 * 5
  def preload_avg(nil, _opts), do: nil

  def preload_avg(dev_alias_or_nil, opts) when is_list(opts) do
    since_ms = Keyword.get(opts, :since_ms, @since_ms_default)

    preload_avg(dev_alias_or_nil, since_ms)
  end

  def preload_avg(dev_alias_or_nil, since_ms) when is_integer(since_ms) do
    import Ecto.Query, only: [from: 2, subquery: 1]

    # select the datapoints within the requested range
    inner_query =
      from(dp in Schema,
        where: dp.reading_at >= ago(^since_ms, "millisecond"),
        order_by: [desc: :reading_at]
      )

    # preload the averge of the datapoints selected by inner_query for this DevAlias
    Repo.preload(dev_alias_or_nil,
      datapoints:
        from(dp in subquery(inner_query),
          order_by: [:dev_alias_id],
          group_by: [:dev_alias_id, :reading_at],
          select: %{temp_c: avg(dp.temp_c), temp_f: avg(dp.temp_c * 1.8 + 32), relhum: avg(dp.relhum)},
          limit: 1
        )
    )
  end

  def purge(%DevAlias{datapoints: datapoints}, :all, batch_size \\ 10) do
    all_ids = Enum.map(datapoints, fn %Schema{id: id} -> id end)
    batches = Enum.chunk_every(all_ids, batch_size)

    for batch <- batches, reduce: {:ok, 0} do
      {:ok, acc} ->
        q = Query.from(dp in Schema, where: dp.id in ^batch)

        {deleted, _} = Repo.delete_all(q)

        {:ok, acc + deleted}
    end
  end

  def reduce_to_avgs(%DevAlias{datapoints: [%Sally.Datapoint{} | _] = datapoints} = dev_alias) do
    Enum.reduce(datapoints, {0, %{}}, fn %Sally.Datapoint{} = datapoint, {count, sums} ->
      {count + 1,
       Map.take(datapoint, [:temp_c, :relhum])
       |> Enum.reduce(%{}, fn
         {key, val}, acc -> if(val, do: Map.put(acc, key, Map.get(sums, key, 0) + val), else: acc)
       end)}
    end)
    |> then(fn {count, sums} -> Enum.into(sums, %{}, fn {key, val} -> {key, val / count} end) end)
    |> then(fn avgs -> Map.put(avgs, :temp_f, Map.get(avgs, :temp_c) * 1.8 + 32) end)
    |> then(fn avgs -> struct(dev_alias, datapoints: [avgs]) end)
  end

  def reduce_to_avgs(dev_alias), do: dev_alias

  def status(name, opts) do
    status_query(name, opts)
    |> Sally.Repo.one()
    |> reduce_to_avgs()
  end

  def status_query(<<_::binary>> = name, opts) when is_list(opts) do
    require Ecto.Query

    since_ms = Keyword.get(opts, :since_ms, @since_ms_default)

    Ecto.Query.from(dev_alias in Sally.DevAlias,
      as: :dev_alias,
      where: [name: ^name],
      join: datapoints in assoc(dev_alias, :datapoints),
      inner_lateral_join:
        latest_datapoints in subquery(
          Ecto.Query.from(datapoint in Sally.Datapoint,
            where: [dev_alias_id: parent_as(:dev_alias).id],
            where: datapoint.reading_at >= ago(^since_ms, "millisecond"),
            order_by: [desc: :reading_at],
            select: [:id]
          )
        ),
      on: latest_datapoints.id == datapoints.id,
      preload: [datapoints: datapoints]
    )
  end
end
