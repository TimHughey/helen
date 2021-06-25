defmodule Sally do
  @moduledoc """
  Documentation for `Sally`.
  """

  alias Alfred.ExecCmd
  alias Sally.{DevAlias, Device}

  def execute(%ExecCmd{} = ec), do: Sally.Execute.cmd(ec)

  def make_alias(name, dev_ident, pio, opts \\ [])
      when is_binary(name) and is_binary(dev_ident) and pio >= 0 do
    opts_map = Keyword.take(opts, [:ttl_ms, :description]) |> Enum.into(%{})
    changes = %{name: name, pio: pio} |> Map.merge(opts_map)

    case Device.find(ident: dev_ident) do
      %Device{} = dev -> DevAlias.create(dev, changes)
      _ -> {:failed, "device does not exist: #{dev_ident}"}
    end
  end

  def status(name, opts \\ []), do: Sally.Status.get(name, opts)
end
