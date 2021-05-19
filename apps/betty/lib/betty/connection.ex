defmodule Betty.Connection do
  @moduledoc false

  require Logger
  use Instream.Connection, otp_app: :betty

  @doc """
  Runs a query and returns the values from the returned results
  """
  @doc since: "0.2.1"
  def run_query(q) when is_binary(q) do
    with %{results: results} when is_list(results) <- query(q),
         %{series: series} <- hd(results),
         %{values: vals} <- hd(series) do
      vals
    else
      error -> error
    end
  end
end
