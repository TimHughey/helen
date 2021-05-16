defmodule SensorTestHelper do
  @moduledoc false

  require Logger

  use HelenTestPretty
  alias Sensor.DB.Device

  def delete_all_devices do
    all_devices = Sensor.devices_begin_with("")

    for device_name <- all_devices do
      case Sensor.device_find(device_name) do
        %_{device: _name} = device ->
          Repo.delete(device)

        error ->
          pretty_puts("failed to delete device:", error)
      end
    end
  end

  defp freshen(ctx) do
    ensure_current = fn %{name: name} = ctx ->
      for _x <- 1..10, reduce: Sensor.status(name) do
        %{ttl_expired: true} ->
          ["ttl expired after freshen: ", name, " (will retry)"] |> Logger.debug()
          Process.sleep(50)
          {ctx, Sensor.status(name)}

        good_status ->
          good_status
      end

      ctx
    end

    ctx
    |> RuthSim.freshen()
    |> Mqtt.wait_for_roundtrip()
    |> ensure_current.()
    |> Map.delete(:device_actual)
    |> load_device_if_needed()
  end

  def freshen_auto(%{freshen: true} = ctx), do: freshen(ctx)
  def freshen_auto(%{freshen: false} = ctx), do: ctx
  def freshen_auto(%{freshen: :auto} = ctx), do: ctx

  def freshen_auto(%{device_actual: %Device{}, name: name} = ctx) do
    case Sensor.status(name) do
      %{ttl_expired: true} -> Map.put(ctx, :freshen, :auto) |> freshen()
      _ -> ctx
    end
  end

  def freshen_auto(passthrough), do: passthrough

  def load_device_if_needed(%{device_actual: %Device{}} = ctx), do: ctx

  def load_device_if_needed(ctx) do
    for _x <- 1..5, reduce: ctx do
      # not found yet
      %{device_actual: x} = ctx when is_nil(x) ->
        Process.sleep(50)
        %{ctx | device_actual: Device.find(ctx.device)}

      # found, spin through remaining range
      %{device_actual: %Device{}} = ctx ->
        ctx

      # haven't attempted find yet
      ctx when is_map_key(ctx, :device_actual) == false ->
        put_in(ctx, [:device_actual], Device.find(ctx.device))
    end
  end

  def make_alias(%{make_alias: true, name: name, device_actual: device_actual} = ctx) do
    import Helen.Time.Helper, only: [local_now: 1, to_binary: 1]

    now_bin = local_now(:default_tz) |> to_binary()

    opts = [
      description: now_bin,
      ttl_ms: ctx[:ttl_ms] || 1000
    ]

    %Device{device: device_default} = device_actual
    device_name = ctx[:device] || device_default

    %{ctx | alias_create: Sensor.alias_create(device_name, name, opts)}
  end

  def make_alias(ctx), do: %{ctx | alias_create: []}

  def make_device(%{make_device: true} = ctx) do
    ctx
    |> RuthSim.make_device()
    |> Mqtt.wait_for_roundtrip()
    |> Map.delete(:make_device)
  end

  def make_device(%{setup_all: true} = ctx) do
    ctx |> Map.delete(:setup_all) |> Map.put(:make_device, true) |> make_device()
  end

  def make_device_if_needed(ctx) do
    device = ctx[:device] || ctx[:default_device]

    case Device.find(device) do
      %Device{} = d -> ctx |> put_in([:device], device) |> put_in([:device_actual], d)
      _ -> Map.put(ctx, :make_device, true) |> Map.put(:device, device) |> make_device()
    end
  end

  def send_datapoints(%{datapoints: {type, count}} = ctx) do
    %{ctx | datapoints: for(_x <- 1..count, do: type)} |> send_datapoints()
  end

  def send_datapoints(%{datapoints: list} = ctx) when is_list(list) do
    for dp <- list, reduce: ctx do
      ctx ->
        # put the datapoint in the ctx for RuthSim
        send_ctx = put_in(ctx, [:datapoint], dp)

        {:sent, _pub_res, sent_dp, rt_ref} = RuthSim.send_datapoint(send_ctx, wait_for_roundtrip: true)

        # ensure there is an accumulator
        ctx = Map.put_new(ctx, :datapoints_sent, [])

        # 1. accumulate the sent datapoints
        # 2. put the sent roundtrip ref
        # 3. wait for round trip
        %{ctx | datapoints_sent: [sent_dp | ctx.datapoints_sent] |> List.flatten()}
        |> put_in([:roundtrip_ref], rt_ref)
        |> Mqtt.wait_for_roundtrip()
    end
  end

  def send_datapoints(ctx), do: ctx

  #
  # # helper for testing other modules
  # def setup_all_for_other_test(ctx) do
  #   dev_prefix = ctx[:dev_prefix]
  #   name = ctx[:device]
  #   cmd_opts = ctx[:cmd_opts] || []
  #
  #   ctx = %{
  #     device: dev_prefix,
  #     pio: :any,
  #     name: name,
  #     execute: %{cmd: :off, name: name, opts: cmd_opts},
  #     ack: true
  #   }
  #
  #   Repo.transaction(fn -> make_device(ctx) |> make_alias() |> execute_cmd() end, [])
  # end
end
