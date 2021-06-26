defmodule Sally do
  @moduledoc """
  Documentation for `Sally`.
  """

  alias Alfred.ExecCmd
  alias Sally.{DevAlias, Device}

  # required as callback from Alfred
  def execute(%ExecCmd{} = ec), do: Sally.Execute.cmd(ec)

  @doc """
    Create an alias to a device and pio

    ```elixir

    Sally.make_alias(alias_name, device_ident, pio, [ttl_ms: 15_000, description: "new dev alias"])

    ```

    **NOTE**
    Device alias names must be unique across *all* device types.

  """
  @doc since: "0.5.2"
  def make_alias(name, dev_ident, pio, opts \\ [])
      when is_binary(name) and is_binary(dev_ident) and pio >= 0 do
    opts_map = Keyword.take(opts, [:ttl_ms, :description]) |> Enum.into(%{})
    changes = %{name: name, pio: pio} |> Map.merge(opts_map)

    case {Device.find(ident: dev_ident), Alfred.available(name)} do
      {%Device{} = dev, true} -> DevAlias.create(dev, changes)
      {%Device{}, false} -> {:failed, "name exists: #{name}"}
      {nil, _} -> {:failed, "device does not exist: #{dev_ident}"}
    end
  end

  # required as callback from Alfred
  def status(name, opts \\ []), do: Sally.Status.get(name, opts)
end
