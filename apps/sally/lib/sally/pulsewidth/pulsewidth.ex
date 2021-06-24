defmodule Sally.PulseWidth do
  alias Sally.{DevAlias, Device, Execute, Status}

  def create_alias(name, dev_ident, pio, opts \\ [])
      when is_binary(name) and is_binary(dev_ident) and pio >= 0 do
    opts_map = Keyword.take(opts, [:ttl_ms, :description]) |> Enum.into(%{})
    changes = %{name: name, pio: pio} |> Map.merge(opts_map)

    case Device.find(ident: dev_ident) do
      %Device{} = dev -> DevAlias.create(dev, changes)
      _ -> {:failed, "device does not exist: #{dev_ident}"}
    end
  end

  def off(name, opts \\ []) do
    alias Alfred.ExecCmd

    %ExecCmd{name: name, cmd: "off", cmd_opts: opts}
    |> Execute.cmd()
  end

  def on(name, opts \\ []) do
    alias Alfred.ExecCmd

    %ExecCmd{name: name, cmd: "on", cmd_opts: opts}
    |> Execute.cmd()
  end

  def status(name, opts \\ []) do
    Status.get(name, opts)
  end
end
