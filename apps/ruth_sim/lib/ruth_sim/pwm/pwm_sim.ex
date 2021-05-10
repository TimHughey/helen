defmodule PwmSim do
  require Logger

  alias PwmKeeper, as: Keeper
  alias PwmSim.Report

  @default_device "pwm/simulated-default"
  @pios 4
  @default_states for x <- 0..(@pios - 1), do: %{pio: x, cmd: "off"}

  defstruct device: @default_device,
            host: RemoteSim.default_host(),
            remote_name: RemoteSim.default_name(),
            mtime: EasyTime.unix_now(:second),
            pio_count: @pios,
            states: @default_states

  def apply_exec_cmd(%PwmSim{} = d, pio, exec_cmd) do
    # NOTE: exec_cmd has already been validated, simply apply it to the device

    # reflect the exec_cmd in the device states for the pio specified in the exec_cmd
    # and simply retain the as is state for all others
    update_states = fn ->
      Enum.map(d.states, fn
        %{pio: state_pio} when state_pio == pio -> put_in(exec_cmd, [:pio], state_pio)
        as_is_state -> as_is_state
      end)
    end

    # apply the exec cmd and update the mtime because this device has changed
    %PwmSim{d | states: update_states.(), mtime: EasyTime.unix_now(:second)}
    # save the updated device
    |> PwmKeeper.save()
  end

  def default_device, do: @default_device
  def default_states, do: @default_states

  # (1 of 2) ctx contains necessary flags and info
  def freshen(%{type: "pwm", freshen: true, device: device} = ctx) do
    alias PwmSim.Report

    put_rc = fn x -> put_in(ctx, [:freshen_rc], x) end

    extras = %{roundtrip_ref: Ecto.UUID.generate()}

    sim = PwmKeeper.load(device) |> PwmKeeper.freshen()

    Report.publish(sim, extras) |> put_rc.()
  end

  # (2 of 2) no match, pass through
  def freshen(passthrough), do: passthrough

  # (1 of 2) this is for us
  def make_device(%{type: "pwm"} = ctx) do
    put_device = fn %PwmSim{} = sim -> put_in(ctx, [:device], sim.device) end

    put_device_and_ref = fn %PwmSim{} = sim, ref ->
      Map.merge(ctx, %{device: sim.device, roundtrip_ref: ref})
    end

    device = ctx[:device] || default_device()

    case create_device_if_needed(device, ctx) do
      {:new, %{rc: :ok}, ref} -> Keeper.load(device) |> put_device_and_ref.(ref)
      {:exists, sim} -> sim |> put_device.()
    end
  end

  # (2 of 2) no match, pass through
  def make_device(passthrough), do: passthrough

  def populate_device(msg, ctx) do
    put_in(msg, [:device], ctx[:device] || default_device())
  end

  def populate_states(msg, ctx) do
    states = ctx[:states] || default_states()
    pio_count = length(states)

    msg
    |> put_in([:states], states)
    |> put_in([:pio_count], pio_count)
    |> PwmKeeper.save()
  end

  defp create_device_if_needed(device, ctx) do
    extras = Map.take(ctx, [:roundtrip_ref])

    case PwmKeeper.load(device) do
      %PwmSim{} = sim -> {:exists, sim}
      _ -> {:new, new_device(ctx) |> Keeper.save() |> Report.publish(extras), ctx.roundtrip_ref}
    end
  end

  defp make_states(ctx) do
    pios = ctx[:pios] || @pios

    for x <- 0..(pios - 1), do: %{pio: x, cmd: "off"}
  end

  defp new_device(ctx) do
    %PwmSim{
      device: ctx[:device] || default_device(),
      host: ctx[:host] || RemoteSim.default_host(),
      remote_name: ctx[:remote_name] || RemoteSim.default_name(),
      mtime: EasyTime.unix_now(:second),
      pio_count: ctx[:pios] || @pios,
      states: make_states(ctx)
    }
  end
end
