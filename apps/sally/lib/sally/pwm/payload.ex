defmodule Sally.PulseWidth.Payload do
  require Logger

  alias Alfred.ExecCmd

  use Sally.MsgOut.Client

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
    [device.host, "pwm", device.ident, ec.inserted_cmd.refid]
    |> publish(assemble_specific_cmd_data(ec), ec.pub_opts)
  end

  defp assemble_specific_cmd_data(%ExecCmd{} = ec) do
    add_ack_if_needed = fn x -> if ec.cmd_opts[:ack] == :host, do: put_in(x, [:ack], true), else: x end

    include_cmd_params_if_needed = fn x ->
      if map_size(ec.cmd_params) > 0, do: put_in(x, [:params], ec.cmd_params), else: x
    end

    %{ec.inserted_cmd.alias.pio => ec.cmd}
    |> add_ack_if_needed.()
    |> include_cmd_params_if_needed.()
  end
end
