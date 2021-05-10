defmodule PwmSim.Report do
  @moduledoc """
  Creating a PwmSim report message
  """

  require Logger

  defstruct device: "unset",
            host: "unset",
            remote_name: nil,
            type: "pwm",
            mtime: EasyTime.unix_now(:second),
            states: [],
            pio_count: 0,
            dev_latency_us: 0,
            cmdack: nil,
            refid: nil,
            roundtrip_ref: nil

  alias PwmSim.Report

  def publish(%PwmSim{} = sim, extras) do
    make_msg(sim, extras)
    |> send()
  end

  defp add_ack_if_needed(%Report{} = rpt, extras) do
    case extras do
      %{ack: true, refid: refid} -> %Report{rpt | cmdack: true, refid: refid}
      _ -> rpt
    end
  end

  defp add_roundtrip_if_requested(%Report{} = rpt, extras) do
    case extras do
      %{roundtrip_ref: ref} -> %Report{rpt | roundtrip_ref: ref}
      _ -> rpt
    end
  end

  defp make_msg(%PwmSim{} = sim, extras) do
    %Report{
      device: sim.device,
      host: sim.host,
      remote_name: sim.remote_name,
      mtime: sim.mtime,
      states: sim.states,
      pio_count: sim.pio_count,
      dev_latency_us: :rand.uniform(10) + :rand.uniform(13)
    }
    |> add_ack_if_needed(extras)
    |> add_roundtrip_if_requested(extras)
    |> prune()
  end

  # defp log(msg, x) when is_binary(msg), do: [msg, ":\n", inspect(x, pretty: true)] |> log()
  # defp log(msg) when is_binary(msg), do: [msg]
  # defp log(iodata) when is_list(iodata), do: Logger.info(iodata)
  # defp log(x), do: ["\n", inspect(x, pretty: true)] |> log()

  defp prune(%Report{} = rpt) do
    remove_nil_values = fn map ->
      for {k, v} <- map, reduce: %{} do
        acc ->
          case {k, v} do
            {_, v} when is_nil(v) -> acc
            {k, v} -> put_in(acc, [k], v)
          end
      end
    end

    rpt
    |> Map.from_struct()
    # discard keys that have nil values
    |> remove_nil_values.()
  end

  defp send(msg) do
    ["msg:\n", inspect(msg, pretty: true)] |> Logger.debug()

    msg |> RuthSim.Mqtt.publish([])
  end
end
