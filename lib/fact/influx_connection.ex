defmodule Fact.Influx do
  @moduledoc false

  use Instream.Connection, otp_app: :helen

  @doc """
    Retrieves a map of all Influx Shards for the specified database

      ### Examples
      iex> Fact.Influx.shards("database")
      %{columns: ["binary", "binary", ...],
        name: "database name",
        values: [<matches columns>]}


  """
  @doc since: "0.0.15"
  def shards(db) do
    Fact.Influx.execute("show shards")
    |> Map.get(:results)
    |> hd()
    |> Map.get(:series)
    |> Enum.find(fn x -> Map.get(x, :name, db) == db end)
  end
end
