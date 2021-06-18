defmodule Sally.Payload do
  require Logger

  # use Sally.MsgOut.Client

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

  alias Sally.Host

  def send_cmd(%Alfred.ExecCmd{inserted_cmd: %Sally.Command{dev_alias: dev_alias}} = ec) do
    # [dev_alias.device.host.ident, dev_alias.device.family, dev_alias.device.ident, ec.inserted_cmd.refid]
    # |> publish(assemble_specific_cmd_data(ec), ec.pub_opts)

    host_id = dev_alias.device.host.ident
    hostname = dev_alias.device.host.name
    family = dev_alias.device.family
    device = dev_alias.device.ident
    refid = ec.inserted_cmd.refid
    data = assemble_specific_cmd_data(ec)

    %Host.Instruct{
      ident: host_id,
      name: hostname,
      data: data,
      filters: [host_id, family, device, refid]
    }
    |> Host.Instruct.send()
  end

  defp assemble_specific_cmd_data(%Alfred.ExecCmd{} = ec) do
    add_ack_if_needed = fn x -> if ec.cmd_opts[:ack] == :host, do: put_in(x, [:ack], true), else: x end

    include_cmd_params_if_needed = fn x ->
      if map_size(ec.cmd_params) > 0, do: put_in(x, [:params], ec.cmd_params), else: x
    end

    %{ec.inserted_cmd.dev_alias.pio => ec.cmd}
    |> add_ack_if_needed.()
    |> include_cmd_params_if_needed.()
  end
end
