defmodule RemoteMsg do
  require Logger
  alias RuthSim.Mqtt

  # (1 of 2) ack and refid are present
  defp add_cmdack_if_needed(msg, %{ack: true, refid: refid}) do
    put_in(msg, [:cmd_ack], true) |> put_in([:refid], refid)
  end

  # (2 of 2) ack and refid are not present
  defp add_cmdack_if_needed(msg, _ctx), do: msg

  defp add_device(%{type: type} = msg, ctx) do
    case type do
      "pwm" -> PwmSim.populate_device(msg, ctx)
      "switch" -> SwitchSim.populate_device(msg, ctx)
    end
  end

  defp add_log_reading(msg, ctx) do
    log_reading = ctx[:log] || false
    put_in(msg, [:log], log_reading)
  end

  defp add_metrics(%{type: type} = msg, ctx) when type in ["pwm", "switch"] do
    put_in(msg, [:dev_latency_us], ctx[:dev_latency_us] || :rand.uniform(25) + :rand.uniform(10))
  end

  defp add_mtime(%{mtime: _} = msg, _ctx) do
    %{msg | mtime: EasyTime.unix_now(:second)}
  end

  defp add_mtime(msg, ctx) do
    mtime = ctx[:mtime] || EasyTime.unix_now(:second)
    put_in(msg, [:mtime], mtime)
  end

  defp add_roundtrip_ref(msg, ctx) do
    case ctx do
      %{roundtrip_ref: rt_ref} -> put_in(msg, [:roundtrip_ref], rt_ref)
      _ctx -> msg
    end
  end

  # (1 of 3) PwmSim
  defp add_states_if_needed(%{type: "pwm"} = msg, ctx), do: PwmSim.populate_states(msg, ctx)

  # (2 of 3) SwitchSim
  defp add_states_if_needed(%{type: "switch"} = msg, ctx), do: SwitchSim.populate_states(msg, ctx)

  # (3 of 3) states not needed
  defp add_states_if_needed(msg, _ctx), do: msg

  # start of a pipeline to create a remote msg
  defp make_msg(ctx) do
    host = ctx[:host] || "ruth.simulated"
    name = ctx[:remote_name] || "remote-sim"
    type = ctx[:type] || "foobar"

    %{host: host, name: name, type: type} |> add_device(ctx) |> populate_msg(ctx)
  end

  def make_then_send_msg(ctx) do
    msg = make_msg(ctx)

    pub_rc = Mqtt.publish(msg, ctx[:pub_opts] || [])

    dev_rpt = %{msg: msg, published: pub_rc}

    put_in(ctx, [:dev_rpt], dev_rpt)
  end

  defp populate_msg(msg, ctx) do
    msg
    |> add_mtime(ctx)
    |> add_states_if_needed(ctx)
    |> add_cmdack_if_needed(ctx)
    |> add_log_reading(ctx)
    |> add_metrics(ctx)
    |> add_roundtrip_ref(ctx)
  end
end
