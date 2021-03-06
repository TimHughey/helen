defmodule Sally do
  @moduledoc """
  Documentation for `Sally`.
  """

  alias Alfred.ExecCmd
  alias Sally.{DevAlias, Device}

  def delete_alias(name_or_id) do
    case DevAlias.delete(name_or_id) do
      {:ok, results} ->
        kn = Alfred.delete(results[:name])
        {:ok, results ++ [alfred: kn]}

      error ->
        error
    end
  end

  # required as callback from Alfred
  def execute(%ExecCmd{} = ec), do: Sally.Execute.cmd(ec)

  @doc """
  Create an alias to a device and pio

  ## Examples:
      iex> opts = [ttl_ms: 15_000, description: "new dev alias"]
      iex> Sally.make_alias(alias_name, device_ident, pio, opts)

  ## Args
  1. `name` alias to device and pio to create
  2. `device_ident` device identifier to be aliased
  3. `pio` device pio to be aliased

  ## NOTES
  * Device alias names must be unique across *all* device types.

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

  defdelegate newest_device, to: Device, as: :newest

  # required as callback from Alfred

  def status(type, name, opts \\ [])
  # (1 of 2) handle mutable devices
  def status(:mutable, name, opts), do: Sally.Mutable.status(name, opts)

  # (2 of 2) handle immutable devices
  def status(:immutable, name, opts), do: Sally.Immutable.status(name, opts)
end
