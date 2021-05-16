defmodule SensorSim do
  require Logger

  alias SensorKeeper, as: Keeper
  alias SensorSim.{Datapoint, Report}

  @default_device "sensor/simulated-default"

  defstruct device: @default_device,
            host: RemoteSim.default_host(),
            remote_name: RemoteSim.default_name(),
            mtime: System.os_time(:second),
            datapoint: Datapoint.default()

  def default_device, do: @default_device
  def default_datapoints, do: Datapoint.default()

  # (1 of 2) ctx contains necessary flags and info
  def freshen(%{type: "sensor", freshen: true, device: device} = ctx) do
    alias SensorSim.Report

    put_rc = fn x -> put_in(ctx, [:freshen_rc], x) end

    extras = %{roundtrip_ref: Ecto.UUID.generate()}

    SensorKeeper.load(device) |> SensorKeeper.freshen() |> Report.publish(extras) |> put_rc.()
  end

  # (2 of 2) no match, pass through
  def freshen(passthrough), do: passthrough

  # (1 of 2) this is for us
  def make_device(%{type: "sensor"} = ctx) do
    put_device = fn %SensorSim{} = sim -> put_in(ctx, [:device], sim.device) end

    put_device_and_ref = fn %SensorSim{} = sim, ref ->
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

  def send_datapoint(ctx) do
    sim = Keeper.load(ctx.device)

    # create the new datapoint if in the ctx or use the existing
    datapoint = Datapoint.create(ctx[:datapoint] || sim.datapoint)

    # reminder, update_datapoint persists the sim
    sim = update_mtime(sim, ctx[:datapoint]) |> update_datapoint(datapoint)

    pub_extras = Map.take(ctx, [:roundtrip_ref])

    {:sent, Report.publish(sim, pub_extras), datapoint, ctx[:roundtrip_ref]}
  end

  defp update_datapoint(%SensorSim{} = sim, dp_map) when is_map(dp_map) do
    %{sim | datapoint: Map.merge(sim.datapoint, dp_map)} |> Keeper.save()
  end

  defp create_device_if_needed(device, ctx) do
    extras = Map.take(ctx, [:roundtrip_ref])

    case SensorKeeper.load(device) do
      %SensorSim{} = sim -> {:exists, sim}
      _ -> {:new, new_device(ctx) |> Keeper.save() |> Report.publish(extras), ctx.roundtrip_ref}
    end
  end

  # mtime updates can be specified using :at in the datapoint map
  # when :at is not present the current mtime is used
  defp update_mtime(%SensorSim{} = sim, params) do
    case params do
      %{at: %DateTime{} = at} -> %SensorSim{sim | mtime: DateTime.to_unix(at, :second)}
      _ -> %SensorSim{sim | mtime: System.os_time(:second)}
    end
  end

  defp new_device(ctx) do
    %SensorSim{
      device: ctx[:device] || default_device(),
      host: ctx[:host] || RemoteSim.default_host(),
      remote_name: ctx[:remote_name] || RemoteSim.default_name(),
      mtime: System.os_time(:second)
      # datapoints are set to default in struct definition
    }
  end
end
