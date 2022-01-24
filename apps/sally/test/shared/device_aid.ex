defmodule Sally.DeviceAid do
  @moduledoc """
  Supporting functionality for creating Sally.Device for testing
  """

  def add(%{device_add: opts, host: %Sally.Host{} = host}) when is_list(opts) do
    device = Ecto.build_assoc(host, :devices)
    type = opts[:auto] || :ds
    ident = opts[:ident] || unique(type)

    base = %{last_seen_at: DateTime.utc_now()}

    insert_opts = [
      on_conflict: {:replace, Sally.Device.columns(:replace)},
      returning: true,
      conflict_target: [:ident]
    ]

    case type do
      :mcp23008 -> %{ident: ident, pios: 8, family: "i2c", mutable: true}
      :ds -> %{ident: ident, family: "ds", pios: 1, mutable: false}
      :pwm -> %{ident: ident, family: "pwm", pios: 4, mutable: true}
    end
    |> Map.merge(base)
    |> Sally.Device.changeset(device)
    |> Sally.Repo.insert(insert_opts)
    |> check_insert_rc()
  end

  def add(_), do: :ok

  def aliases(%Sally.Device{} = device) do
    Sally.Device.load_aliases(device)
  end

  def check_insert_rc(insert_rc) do
    case insert_rc do
      {:ok, %Sally.Device{} = x} -> %{device: x}
      error -> raise(inspect(error, pretty: true))
    end
  end

  def next_pio(%Sally.Device{} = device) do
    device = Sally.Device.load_aliases(device)

    all_pios = 0..(device.pios - 1) |> Enum.to_list()
    used_pios = for %Sally.DevAlias{pio: x} <- device.aliases, do: x

    available_pios = all_pios -- used_pios

    case available_pios do
      [] -> raise("pios exhausted")
      [x | _] -> x
    end
  end

  # NOTE: for use by other Sally test aid mdules
  def split_opts(opts), do: Keyword.split(opts, supported_opts())
  def supported_opts, do: [:auto, :pios]

  def unique(type) when is_atom(type) do
    x = Ecto.UUID.generate() |> String.split("-") |> Enum.at(4)

    case type do
      :ds -> "ds.#{x}"
      :mcp23008 -> "i2c.#{x}.mcp23008.20"
      :pwm -> "pwm.#{x}"
    end
  end
end
