defmodule Switch.Payload do
  require Logger

  alias Switch.DB.Alias, as: Schema

  # reference for random command
  # def example(%Device{} = switch_dev) do
  #   cmd = %{
  #     name: "random fade",
  #     type: "random",
  #     random: %{
  #       min: 256,
  #       max: 2048,
  #       primes: 25,
  #       step_ms: 50,
  #       step: 7,
  #       priority: 7
  #     }
  #   }
  #
  #   create_outbound_cmd(switch_dev, cmd, [])
  # end

  def send_cmd(%Schema{} = _a, _cmd, _opts), do: nil

  defp create_outbound_cmd(%Schema{device: d} = a, cmd_map, opts) when is_list(opts) do
    # default to the host ack'ing rhe command
    ack = opts[:ack] || :host

    x = %{
      payload: "switch state",
      mtime: System.os_time(:second),
      host: d.host,
      device: d.device,
      pio: a.pio,
      refid: opts[:refid],
      ack: ack == :host,
      exec: prune_cmd_map(cmd_map) |> List.wrap()
    }

    Logger.debug(["\n", inspect(x, pretty: true)])

    x
  end

  defp prune_cmd_map(cmd_map), do: Map.drop(cmd_map, [:name])
end
