defmodule Sensor.DB.DataPoint do
  @moduledoc """
  Database functionality for Sensor DataPoint
  """

  require Logger

  use Ecto.Schema
  require Ecto.Query
  alias Ecto.Query

  alias Sensor.DB.Alias
  alias Sensor.DB.DataPoint, as: Schema

  schema "sensor_datapoint" do
    field(:temp_c, :float)
    field(:relhum, :float)
    field(:reading_at, :utc_datetime_usec)

    belongs_to(:alias, Alias)
  end

  def add(%Alias{} = a, dp_map) do
    # associate the new command with the Alias
    new_dp = Ecto.build_assoc(a, :datapoints)

    cs = Map.take(dp_map, [:temp_c, :relhum]) |> put_in([:reading_at], DateTime.utc_now())

    changeset(new_dp, cs) |> Repo.insert(returning: true)
  end

  # (1 of 2) insure changes are a map
  # def changeset(%Schema{} = c, changes) when is_list(changes) do
  #   changeset(c, Enum.into(changes, %{}))
  # end

  def changeset(%Schema{} = c, changes) when is_map(changes) do
    alias Ecto.Changeset

    c
    |> Changeset.cast(changes, columns(:cast))
    |> Changeset.validate_required([:temp_c, :reading_at, :alias_id])
    |> Changeset.validate_number(:temp_c, greater_than: -30.0, less_than: 55.0)
    |> Changeset.validate_number(:relhum, greater_than: 0.0, less_than_or_equal_to: 100.0)
  end

  def purge(%Alias{datapoints: datapoints}, :all) do
    all_ids = Enum.map(datapoints, fn %Schema{id: id} -> id end)
    batches = Enum.chunk_every(all_ids, 10)

    for batch <- batches, reduce: {:ok, 0} do
      {:ok, acc} ->
        q = Query.from(dp in Schema, where: dp.id in ^batch)

        {deleted, _} = Repo.delete_all(q)

        {:ok, acc + deleted}
    end
  end

  # helpers for changeset columns
  defp columns(:all) do
    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
  end

  defp columns(:cast), do: columns(:all)
end
