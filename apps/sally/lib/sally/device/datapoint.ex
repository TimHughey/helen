defmodule Sally.Datapoint do
  @moduledoc """
  Database functionality for Sensor DataPoint
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

  @deprecated "Use Sally.Datapoint.add/4 instead"
  def add(%DevAlias{} = a, dp_map, reading_at \\ nil) do
    at = reading_at || DateTime.utc_now()
    # associate the new command with the DevAlias
    new_dp = Ecto.build_assoc(a, :datapoints)

    dp_map
    |> Map.take([:temp_c, :relhum])
    |> Map.put(:reading_at, at)
    |> changeset(new_dp)
    |> Repo.insert(returning: true)
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
end
