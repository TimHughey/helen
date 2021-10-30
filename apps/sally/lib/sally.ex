defmodule Sally do
  @moduledoc """
  Documentation for `Sally`.
  """

  alias Alfred.ExecCmd
  alias Sally.{DevAlias, Device, Host, Repo}

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

  def host_devices(name) do
    host = Host.find_by_name(name) |> Repo.preload(:devices)

    with %Host{} = host <- Host.find_by_name(name),
         %Host{devices: devices} <- Repo.preload(host, :devices) do
      for %Device{ident: ident} <- devices, do: ident
    else
      _ -> {:not_found, host}
    end
  end

  def host_info(name) do
    Sally.Host.find_by_name(name)
  end

  def host_name(ident, new_name) do
    case Host.find_by_ident(ident) do
      %Host{name: name} when name == new_name -> :no_change
      %Host{} = x -> Host.changeset(x, %{name: new_name}, [:name]) |> Repo.update()
      _ -> :not_found
    end
  end

  def host_ota(name, opts \\ []) do
    Host.Firmware.ota(name, opts)
  end

  def host_profile(hostname, profile_name) do
    case Host.find_by_name(hostname) do
      %Host{profile: profile} when profile == profile_name -> :no_change
      %Host{} = x -> Host.changeset(x, %{profile: profile_name}, [:profile]) |> Repo.update()
      _ -> :not_found
    end
  end

  def host_restart(name) when is_binary(name), do: Host.Restart.now(name)

  def host_setup(:unnamed, opts) do
    case Host.unnamed() do
      [%Host{} = host] -> Host.setup(host, opts)
      [] -> {:all_named, []}
      multiple -> {:multiple, multiple}
    end
  end

  def host_setup(ident, opts) when is_binary(ident) do
    case Host.find_by_ident(ident) do
      %Host{} = host -> Host.setup(host, opts)
      _ -> {:not_found, ident}
    end
  end

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

    case {Device.find(ident: dev_ident), Alfred.available?(name)} do
      {%Device{} = dev, true} -> DevAlias.create(dev, changes)
      {%Device{}, false} -> {:failed, "name exists: #{name}"}
      {nil, _} -> {:failed, "device does not exist: #{dev_ident}"}
    end
  end

  def move_device_aliases(src_ident, dest_ident), do: Sally.Device.move_aliases(src_ident, dest_ident)

  defdelegate newest_device, to: Device, as: :newest

  # required as callback from Alfred
  # function head
  def status(type, name, opts \\ [])

  # (1 of 2) handle mutable devices
  def status(:mutable, name, opts), do: Sally.Mutable.status(name, opts)

  # (2 of 2) handle immutable devices
  def status(:immutable, name, opts), do: Sally.Immutable.status(name, opts)
end
