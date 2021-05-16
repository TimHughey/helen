defmodule Sensor.DataPoints do
  require Logger

  alias Sensor.DB.{Alias, DataPoint, Device}

  # accepts inbound msg, returns inbound msg augmented with datapoints rc
  def inbound_msg(in_msg) do
    case in_msg do
      # 1. fail when there aren't datapoints in the msg
      %{datapoints: []} ->
        put_datapoints_rc(in_msg, {:failed, "inbound msg datapoints == []"})

      # 2. succeed {:ok, []} when there aren't any aliases (nothing is stored)
      %{datapoints: _, device: {:ok, %Device{aliases: []}}} ->
        put_datapoints_rc(in_msg, {:ok, []})

      # 3. we have aliases and datapoints
      %{datapoints: in_dp, device: {:ok, d}} ->
        store_datapoints(d.aliases, in_dp) |> put_datapoints_rc(in_msg)

      # 4. a strange situation
      _ ->
        put_datapoints_rc(in_msg, {:failed, "inbound msg :datapoints key not found or device update failed"})
    end
  end

  # (1 of 2) just put whatever is passed (typically an failure)
  defp put_datapoints_rc(msg, rc) when is_map(msg), do: put_in(msg, [:datapoints_rc], rc)

  # (2 of 2) examine the results list and determine an overall rc
  defp put_datapoints_rc(results, msg) when is_list(results) do
    rc_from_result = fn rc, x ->
      case {rc, x[:success]} do
        {:ok, true} -> :ok
        {:ok, false} -> :failed
      end
    end

    # 1. delete the processed datapoints
    # 2. add datapoints_rc for final validation
    msg = Map.delete(msg, :datapoints) |> put_in([:datapoints_rc], {:ok, []})

    for result <- results, reduce: msg do
      # found an error, skip the remaining results
      %{datapoints_rc: {rc, acc}} = msg ->
        %{msg | datapoints_rc: {rc_from_result.(rc, result), [acc, result] |> List.flatten()}}
    end
  end

  defp store_datapoints(aliases, datapoint_list) do
    for %Alias{} = a <- aliases, datapoint_map <- datapoint_list do
      case DataPoint.add(a, datapoint_map) do
        {:ok, %DataPoint{} = x} -> %{name: a.name, success: true, schema: a, datapoint: x}
        {:error, text} -> %{name: a.name, success: false, error: text}
      end
    end
  end
end
