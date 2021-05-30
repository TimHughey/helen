defmodule Sally.PulseWidth.Payload do
  require Logger

  alias Alfred.ExecCmd
  alias Sally.Mqtt
  alias Sally.MsgOut
  alias Sally.PulseWidth.DB.{Alias, Command}

  # reference for random command
  # def example(%Device{} = pwm_dev) do
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
  #   create_outbound_cmd(pwm_dev, cmd, [])
  # end

  def send_cmd(%ExecCmd{inserted_cmd: %Command{alias: %Alias{device: device}}} = ec) do
    %MsgOut{host: device.host, device: device.ident, data: assemble_specific_cmd_data(ec)}
    |> MsgOut.apply_opts(ec.pub_opts)
    |> Mqtt.publish()
  end

  defp assemble_specific_cmd_data(%ExecCmd{} = ec) do
    ack = ec.cmd_opts[:ack] || :host

    %{cmd: ec.cmd, pio: ec.inserted_cmd.alias.pio, refid: ec.inserted_cmd.refid, ack: ack == :host}
    |> include_cmd_params_if_needed(ec.cmd_params)
  end

  defp include_cmd_params_if_needed(data, cmd_params) when map_size(cmd_params) > 0 do
    # cmd_params = Enum.into(cmd_params, []) |> List.wrap()

    put_in(data, [:exec], cmd_params)
  end

  defp include_cmd_params_if_needed(data, _cmd_params), do: data

  #
  # def send_cmd(%Schema{} = a, cmd, opts) do
  #   create_outbound_cmd(a, cmd, opts) |> Mqtt.publish(opts)
  # end

  # defp create_outbound_cmd(%Schema{device: d} = a, cmd_map, opts) when is_list(opts) do
  #   # default to the host ack'ing rhe command
  #   ack = opts[:ack] || :host
  #
  #   %{
  #     payload: "pwm state",
  #     mtime: System.os_time(:second),
  #     host: d.host,
  #     device: d.device,
  #     pio: a.pio,
  #     refid: opts[:refid],
  #     ack: ack == :host,
  #     exec: prune_cmd_map(cmd_map) |> List.wrap()
  #   }
  # end
  #
  # defp prune_cmd_map(cmd_map), do: Map.drop(cmd_map, [:name])
end
