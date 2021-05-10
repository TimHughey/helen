defmodule SwitchTestHelper do
  @moduledoc false

  require Logger

  use HelenTestPretty
  alias Switch.DB.Device

  def delete_all_devices do
    all_devices = Switch.devices_begin_with("")

    for device_name <- all_devices do
      case Switch.device_find(device_name) do
        %_{device: _name} = device ->
          Repo.delete(device)

        error ->
          pretty_puts("failed to delete device:", error)
      end
    end
  end

  # (1 of 2) if there is a cmd map in the ctx execute it
  def execute_cmap(%{cmd_map: %{name: _} = cmap} = ctx), do: %{ctx | execute_rc: Switch.execute(cmap)}

  def execute_cmap(%{cmd_map: cmap, name: name} = ctx) do
    %{ctx | cmd_map: put_in(cmap, [:name], name)} |> execute_cmap()
  end

  def execute_cmap(ctx), do: ctx

  def find_available_pio(%Device{} = d) do
    import Device, only: [pio_count: 1]

    for pio <- 0..(pio_count(d) - 1), reduce: false do
      false -> if Device.pio_aliased?(d, pio) == false, do: pio, else: false
      pio when is_integer(pio) -> pio
    end
  end

  defp freshen(ctx) do
    ensure_current = fn %{name: name} = ctx ->
      for _x <- 1..10, reduce: Switch.status(name) do
        %{ttl_expired: true} ->
          ["ttl expired after freshen: ", name, " (will retry)"] |> Logger.info()
          Process.sleep(50)
          {ctx, Switch.status(name)}

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
    case Switch.status(name) do
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

  def make_alias(%{make_alias: true, pio: pio, name: name, device_actual: device_actual} = ctx) do
    import Helen.Time.Helper, only: [local_now: 1, to_binary: 1]

    now_bin = local_now(:default_tz) |> to_binary()

    opts = [
      description: now_bin,
      ttl_ms: ctx[:ttl_ms] || 1000
    ]

    %Device{device: device_default} = device_actual
    device_name = ctx[:device] || device_default

    pio = (pio == :any && find_available_pio(device_actual)) || pio

    Logger.debug(["pio: ", inspect(pio)])

    %{ctx | alias_create: Switch.alias_create(device_name, name, pio, opts)}
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
