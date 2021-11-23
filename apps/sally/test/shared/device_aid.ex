defmodule Sally.DeviceAid do
  alias Sally.{DevAlias, Device, Host, Repo}

  def add(%{device_add: opts, host: %Host{} = host}) when is_list(opts) do
    device = Ecto.build_assoc(host, :devices)
    type = opts[:auto] || :ds
    ident = opts[:ident] || unique(type)

    base = %{last_seen_at: DateTime.utc_now()}

    insert_opts = [
      on_conflict: {:replace, Device.columns(:replace)},
      returning: true,
      conflict_target: [:ident]
    ]

    case type do
      :mcp23008 -> %{ident: ident, pios: 8, family: "i2c", mutable: true}
      :ds -> %{ident: ident, family: "ds", pios: 1, mutable: false}
      :pwm -> %{ident: ident, family: "pwm", pios: 4, mutable: true}
    end
    |> Map.merge(base)
    |> Device.changeset(device)
    |> Repo.insert(insert_opts)
    |> then(fn
      {:ok, %Device{} = x} -> %{device: x}
      error -> Should.prettyi(error)
    end)
  end

  def add(_), do: :ok

  def aliases(%Device{} = device) do
    Device.load_aliases(device)
  end

  def next_pio(%Device{} = device) do
    device = Device.load_aliases(device)

    all_pios = 0..(device.pios - 1) |> Enum.to_list()
    used_pios = for %DevAlias{pio: x} <- device.aliases, do: x

    available_pios = all_pios -- used_pios

    case available_pios do
      [] -> nil
      [x | _] -> x
    end
  end

  def unique(type) when is_atom(type) do
    x = Ecto.UUID.generate() |> String.split("-") |> Enum.at(4)

    case type do
      :ds -> "ds.#{x}"
      :mcp23008 -> "i2c.#{x}.mcp23008.20"
      :pwm -> "pwm.#{x}"
    end
  end
end
