defmodule Sally.Command.Payload do
  @moduledoc false

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

  def send_cmd(%Sally.Command{} = cmd, opts) do
    send_opts = send_opts(opts)

    %{refid: refid, dev_alias: %{device: %{host: host} = device}} = cmd

    [
      ident: host.ident,
      name: host.name,
      subsystem: device.family,
      data: cmd_data(cmd, opts),
      filters: [device.ident, refid],
      opts: send_opts
    ]
    |> Sally.Host.Instruct.send()
  end

  defmacrop put_key(val) do
    quote bind_quoted: [val: val], do: Map.put(var!(acc), var!(key), val)
  end

  def cmd_data(cmd, opts) do
    %{cmd: cmd, dev_alias: %{pio: pio}} = cmd

    cmd_opts = Keyword.get(opts, :cmd_opts, []) |> Keyword.put_new(:ack, :host)
    params = Keyword.get(opts, :cmd_params, :none)

    opts = [{:params, params} | cmd_opts]

    # NOTE: Ruth hosts require :pin, :cmd and :ack.  include :pio for future capability
    #       when Ruth is updated to use :pio for consistency with Sally
    required = %{pin: pio, pio: pio, cmd: cmd}

    Enum.reduce(opts, required, fn
      {:ack = key, :immediate}, acc -> put_key(false)
      {:ack = key, _val}, acc -> put_key(true)
      {:params = key, %{} = params}, acc -> put_key(params)
      {:params = key, [_ | _] = params}, acc -> Enum.into(params, %{}) |> put_key()
      _, acc -> acc
    end)
  end

  def send_opts(opts) do
    Keyword.get(opts, :cmd_opts, []) |> Keyword.take([:echo])
  end
end
