defmodule Sally.DeviceAid do
  @moduledoc """
  Supporting functionality for creating Sally.Device for testing
  """

  # NOTE: test context support
  def add(%{device_add: opts, host: %{id: _} = host}) when is_list(opts) do
    %{device: add(opts, host)}
  end

  def add(_), do: :ok

  def add(opts, %Sally.Host{} = host) when is_list(opts) do
    type = opts[:auto] || :ds
    ident = opts[:ident] || unique(type)
    create_at = DateTime.utc_now()

    params = %{data: %{pins: pin_data(ident)}, host: host, subsystem: subsystem(ident)}

    Sally.Device.create(ident, create_at, params)
  end

  def next_pio(%Sally.Device{pios: pios} = device) do
    pios = 0..(pios - 1)
    next = Enum.find(pios, :none, fn pio -> not Sally.Device.pio_aliased?(device, pio) end)

    if is_integer(next), do: next, else: raise("pios exhausted")
  end

  def pin_data(ident) do
    case ident do
      <<"ds"::binary, _::binary>> -> 0..0
      <<"i2c"::binary, _::binary>> -> 0..7
      <<"pwm"::binary, _::binary>> -> 0..3
    end
    # NOTE: this simulates the pin data from the remote host, nil is ignored
    # by Sally.Device.create/3
    |> Enum.map(fn n -> {n, nil} end)
  end

  def subsystem(ident) do
    case ident do
      <<"ds"::binary, _::binary>> -> "immut"
      <<"i2c"::binary, _::binary>> -> "mut"
      <<"pwm"::binary, _::binary>> -> "mut"
    end
  end

  # NOTE: for use by other Sally test aid mdules
  def split_opts(opts), do: Keyword.split(opts, supported_opts())
  def supported_opts, do: [:auto, :pios]

  def unique(type) when is_atom(type) do
    x = Ecto.UUID.generate() |> String.split("-") |> Enum.at(4)

    case type do
      :ds -> "ds." <> x
      :mcp23008 -> "i2c.#{x}.mcp23008.20"
      :pwm -> "pwm." <> x
    end
  end
end
