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

  @doc """
  Add a DevAlias to an existing Device

  ## Examples:
      iex> opts = [device: "i2c.7af1e2b706fc.mcp23008.20", name: "alias name", pio: 1,
      ...>         description: "power", ttl_ms: 15_000]
      iex> Sally.device_add_alias(opts)

  ## Opts
  1. `device:`       when binary denotes device for new alias | :latest to use latest discovered device
  2. `name:`         alias name
  3. `pio:`          pio to alias (required for mutable devices, optional for immutable devices)
  4. `description:`  description of the alias (optional)
  5. `ttl_ms:`       ttl (in ms) of the alias (used to determine status currency)

  ## Returns:
  1. `%Sally.DevAlias{}`    on success
  2. `{:error, binary}`     where binary indicates missing or invalid option
  3. `{:not_found, device}` when device is not found
  4. `{:name_taken, msg}`   when the alias name is already known
  5. `{:error, list}`       when changeset validation fails the list of failures is returned

  ## Notes:
  1. The device alias is created in the database but will not be known externally (e.g. Alfred)
     until a reading is received from the host where the physical device is attached.
  """
  @doc since: "0.5.7"
  def device_add_alias(opts) when is_list(opts) do
    with {:device_opt, device} when is_binary(device) <- {:device_opt, opts[:device]},
         {:device, %Device{} = device} <- {:device, Device.find(ident: device)},
         {:name_opt, name} when is_binary(name) <- {:name_opt, opts[:name]},
         {:available, true} <- {:available, Alfred.available?(name)},
         {:pio_opt, pio} when is_integer(pio) <- {:pio_opt, Device.pio_check(device, opts)} do
      final_opts = [name: name, pio: pio] ++ Keyword.take(opts, [:description, :ttl_ms])

      case DevAlias.create(device, final_opts) do
        {:ok, %DevAlias{} = x} -> x
        {:error, %Ecto.Changeset{errors: errors}} -> {:error, errors}
      end
    else
      {:device_opt, :latest} -> Keyword.replace(opts, :device, device_latest()) |> device_add_alias()
      {:device_opt, nil} -> {:error, ":device missing or non-binary"}
      {:device, nil} -> {:not_found, opts[:device]}
      {:name_opt, nil} -> {:error, ":name missing or non-binary"}
      {:available, false} -> {:name_taken, opts[:name]}
      {:pio_opt, _} -> {:error, ":pio missing (and is required) or non-integer"}
    end
  end

  def device_latest(opts \\ [schema: false, age: [hours: -1]]), do: Device.latest(opts)

  @doc """
  Move device aliases from one device to another

  ## Examples:
      iex> Sally.move_device_aliases(from: "src device ident", to: "dest device ident")

  ## Opts
  1. `from:` device identifier to move aliases from
  2. `to:` when binary the destination device | :latest for most recently discovered device

  ## NOTES
  * Destination (`to:`) device must have zero (0) aliases

  """
  @doc since: "0.5.7"
  def device_move_aliases(opts) when is_list(opts) do
    with {:from, from_ident} when is_binary(from_ident) <- {:from, opts[:from]},
         {:to, to_ident} when is_binary(to_ident) <- {:to, opts[:to]} do
      Device.move_aliases(from_ident, to_ident)
    else
      {:from, nil} -> {:error, ":from missing or non-binary"}
      {:to, nil} -> {:error, ":to missing or non-binary"}
      {:to, :latest} -> Keyword.replace(opts, :to, device_latest()) |> device_move_aliases()
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
    Host.find_by_name(name)
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

  # required as callback from Alfred
  # function head
  def status(type, name, opts \\ [])

  # (1 of 2) handle mutable devices
  def status(:mutable, name, opts), do: Sally.Mutable.status(name, opts)

  # (2 of 2) handle immutable devices
  def status(:immutable, name, opts), do: Sally.Immutable.status(name, opts)
end
