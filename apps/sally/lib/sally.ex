defmodule Sally do
  @moduledoc """
  Documentation for `Sally`.
  """

  alias Alfred.ExecCmd
  alias Sally.{Command, DevAlias, Device, Host, Repo}

  @doc """
  Deletes a DevAlias by name or id

  ## Examples
  ```
  # delete a known name
  Sally.devalias_delete("devalias name")
  #=> {:ok, ["devalias name"]}

  # delete a known name by database id, ret
  Sally.devalias_delete(76758)
  #=> {:ok, ["devalias for id 76758"]}

  ```

  If the name or id is found, `{:ok, [names, ...]}` is returned.

  If the name or id isn't found, `{:not_found, name_or_id}` is returned

  It returns `{:error, changeset}` for validation failures (see `c:Ecto.Repo.delete/2`).

  ### Note
  > If the name is registered with `Alfred` it is deleted.

  """
  @type devalias_delete_result() :: [String.t(), ...] | {:error, term()} | {:not_found, String.t()}
  @type name_or_id() :: String.t() | pos_integer()
  @spec devalias_delete(name_or_id()) :: devalias_delete_result()
  def devalias_delete(name_or_id) do
    case DevAlias.delete(name_or_id) do
      {:ok, results} ->
        {:ok, results ++ [alfred: Alfred.names_delete(results[:name])]}

      error ->
        error
    end
  end

  @doc """
  Show info of a DevAlias

  ## Examples
  ```
  # get info on a specific DevAlias
  Sally.devalias_info("dev alias")
  ```

  ## Options
  * `:summary` - map of most revelant info (default)
  * `:raw` - complete schema

  If the name is not found, `{:not_found, name}` is returned.

  """
  @doc since: "0.5.9"
  def devalias_info(name, opts \\ [:summary]) when is_binary(name) do
    with %DevAlias{} = dev_alias <- Repo.get_by(DevAlias, name: name),
         dev_alias <- DevAlias.load_info(dev_alias) do
      cond do
        [:summary] == opts ->
          assoc = %{
            device: Device.summary(dev_alias.device),
            host: Host.summary(dev_alias.device.host),
            cmd: Command.summary(dev_alias.cmds)
          }

          DevAlias.summary(dev_alias) |> Map.merge(assoc)

        [:raw] == opts ->
          dev_alias

        true ->
          {:bad_args, opts}
      end
    else
      nil -> {:not_found, name}
    end
  end

  @doc """
  Renames an existing DevAlias

  ## Examples
  ```
  Sally.devalias_rename([from: "old name", to: "new name"])
  ```

  ## Options
  * `:from` - name of existing DevAlias
  * `:to` - desired new name

  Successful rename returns `:ok`.

  If the name is not found, `{:not_found, name}` is returned.

  If the `:to` name already exists, `{:name_taken, to_name}` is returned.

  If the passed iist of opts isn't valid, `{:bad_args, opts}` is returned.

  """
  @doc since: "0.5.9"
  def devalias_rename(opts) when is_list(opts) do
    alfred = opts[:alfred] || Alfred

    case DevAlias.rename(opts) do
      %DevAlias{} ->
        alfred.names_delete(opts[:from])
        :ok

      error ->
        error
    end
  end

  @doc """
  Add a logical name for a physical device/pio combination.

  `Sally.DevAlias` are logical names for invoking actions (e.g. `Sally.execute/2`,
  `Sally.status/2`) on mutable and immutable physical devices.

  ## Examples:
  ```
  # opts for the new DevAlias
  opts =
    [device: "i2c.7af1e2b706fc.mcp23008.20", name: "alias name", pio: 1,
    description: "power", ttl_ms: 15_000]

  # add the new DevAlias
  Sally.device_add_alias(opts)

  ```

  ## Options
  * `:device` - ident of underlying Device. May also be `:latest` to automatically select the most recently discovered (inserted) Device.

  * `:name` - name of the new `DevAlias`

  * `:pio` - the pio of the new `DevAlias`. This is required for mutable devices with multiple pios and optional for immutable devices with a single pio.

  * `:description` - description of the new DevAlias (optional)

  * `:ttl_ms` - duration (in ms) status is current between readings of the underlying physical device

  ## Returns
  1. `Sally.DevAlias` - on success
  2. `{:error, binary}` - on error, the binary is a message describing the error
  3. `{:not_found, device}` - when device is not found
  4. `{:name_taken, msg}` - when the name already exists
  5. `{:error, list}` - when the changeset validation fails

  > The `DevAlias` is created in the database but isn't available for use
  > externally (i.e. `Alfred`) until a status update is received via MQTT for the
  > underlying device.
  """
  @doc since: "0.5.7"
  def device_add_alias(opts) when is_list(opts) do
    with {:device_opt, device} when is_binary(device) <- {:device_opt, opts[:device]},
         {:device, %Device{} = device} <- {:device, Device.find(ident: device)},
         {:name_opt, name} when is_binary(name) <- {:name_opt, opts[:name]},
         {:available, true} <- {:available, Alfred.names_available?(name)},
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

  @doc """
  Find the most recent Device added to Sally

  ## Examples:
      iex> Sally.device_latest()

      iex> Sally.device_latest(age: [hours: -2])

      iex> Sally.device_latest(schema: true)

  ## Opts
  1. 'age: Timex.shift_opts()'  now shifted shift opts to set threshold past DateTime
  2. `schema: boolean()` device identifier to move aliases from
  """
  @doc since: "0.5.9"
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
  def execute(%ExecCmd{} = ec, opts \\ []) when is_list(opts), do: Sally.Execute.cmd(ec, opts)

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

  @doc """
  Find the most recent Host added to Sally

  ## Examples:
      iex> Sally.host_latest()

      iex> Sally.host_latest(age: [hours: -2])

      iex> Sally.host_latest(schema: true)

  ## Opts
  1. 'age: Timex.shift_opts()'  now shifted shift opts to set threshold past DateTime
  2. `schema: boolean()` device identifier to move aliases from

  See `Sally.host_ota/2` for additional options.
  """
  @doc since: "0.5.9"
  def host_latest(opts \\ [schema: false, age: [hours: -1]]), do: Host.latest(opts)

  @doc """
  Initiate an OTA for specific host name

  * `file:` the firmware file, defaults to `latest.bin`
  * `valid_ms:`  milliseconds to wait before marking OTA valid, defaults to `60_000`
  """
  def host_ota(name, opts \\ []) when is_binary(name) do
    Host.Firmware.ota(name, opts)
  end

  def host_ota_live(opts \\ []) do
    Host.Firmware.ota(:live, opts)
  end

  def host_profile(hostname, profile_name) do
    case Host.find_by_name(hostname) do
      %Host{profile: profile} when profile == profile_name -> :no_change
      %Host{} = x -> Host.changeset(x, %{profile: profile_name}, [:profile]) |> Repo.update()
      _ -> :not_found
    end
  end

  # def host_replace_hardware(opts) when is_list(opts) do
  #   from = opts[:from_ident]
  #   to = opts[:to_ident]
  # end

  @doc """
  Renames an existing Host

  ## Examples:
      iex> Sally.host_rename(from: "existing name", to: "new name")

  ## Returns:
    1. `:ok`                       -> rename successful
    2. `{:not_found, String.t()}`  -> a host with `from:` name does not exist
    2. `{:name_taken, String.t()}` -> requested name is already in use
    3. `{:bad_args, list()}`       -> the opts passed failed validation

  ## Opts
  1. `from:` host name to rename
  2. `to:`   new host name
  """
  @doc since: "0.5.9"
  def host_rename(opts) when is_list(opts) do
    case Host.rename(opts) do
      %Host{} -> :ok
      error -> error
    end
  end

  def host_restart(name, opts \\ []) when is_binary(name) do
    Host.Restart.now(name, opts)
  end

  @doc """
  Retire an existing host

  The named host is retired by:

   1. Setting the host name equal to the ident
   2. Removing authorization
   3. Setting the reset_reason to retired

  ## Examples:
      iex> Sally.host_retire("name of host to retire")

  """
  @doc since: "0.5.9"
  def host_retire(name) when is_binary(name) do
    case Host.find_by_name(name) do
      %Host{} = x -> Host.retire(x)
      _ -> {:not_found, name}
    end
  end

  @doc """
  Setup unnamed Hosts

  ## Examples:
      iex> opts = [name: "new host name", profile: "all_engines"]
      iex> Sally.host_setup(:unnamed, opts)

      iex> Sally.host_setup("ruth.1234567890", opts)

  ## Opts
  1. 'name: String.t()'    name to assign to host
  2. `profile: String.t()` profile to assign to host
  """
  @doc since: "0.5.9"
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

  """
  @doc since: "0.5.10"
  def just_saw(%Device{} = device, dev_aliases) when is_list(dev_aliases) do
    alias Alfred.{JustSaw, SeenName}

    type = Device.type(device)

    JustSaw.new(type, dev_aliases, &SeenName.from_schema/1, {:module, __MODULE__})
    |> Alfred.just_saw()
  end

  # def just_saw([%DevAlias{device_id: dev_id} | _] = dev_aliases) do
  #   alias Alfred.{JustSaw, SeenName}
  #
  #   Device.type(dev_id)
  #   |> JustSaw.new(dev_aliases, &SeenName.from_schema/1, {:module, __MODULE__})
  #   |> Alfred.just_saw()
  # end

  # required as callback from Alfred
  # function head
  def status(type, name, opts \\ [])

  # (1 of 2) handle mutable devices
  def status(:mut_status, name, opts), do: Sally.Mutable.status(name, opts)

  # (2 of 2) handle immutable devices
  def status(:imm_status, name, opts), do: Sally.Immutable.status(name, opts)
end
