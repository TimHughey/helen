defmodule Sally do
  @moduledoc """
  Documentation for `Sally`.
  """

  @doc since: "0.7.16"
  def clean_up(:devices, opts) do
    Sally.Device.cleanup(opts)
  end

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
  def devalias_delete(name_or_id), do: Sally.DevAlias.delete(name_or_id)

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
  @info_preload [preload: :device_and_host]
  def devalias_info(name, opts \\ [:summary]) when is_binary(name) do
    with %{nature: _} = dev_alias <- Sally.DevAlias.load_alias(name) do
      dev_alias = Sally.DevAlias.status_lookup(dev_alias, @info_preload)

      cond do
        [:summary] == opts ->
          assoc = %{
            device: Sally.Device.summary(dev_alias.device),
            host: Sally.Host.summary(dev_alias.device.host),
            cmd: Sally.Command.summary(dev_alias.status)
          }

          Sally.DevAlias.summary(dev_alias) |> Map.merge(assoc)

        [:raw] == opts ->
          dev_alias

        true ->
          {:bad_args, opts}
      end
    else
      nil -> {:not_found, name}
    end
  end

  @device_types [:imm, :mut]
  def devalias_names(type) when type in @device_types do
    Sally.DevAlias.names_query(type) |> Sally.Repo.all() |> Enum.sort()
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

    case Sally.DevAlias.rename(opts) do
      %{} ->
        alfred.name_unregister(opts[:from])
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
  def device_add_alias(<<_::binary>> = ident, opts) when is_list(opts) do
    device = Sally.Device.find(ident)
    unless match?(%{}, device), do: raise("not found: #{ident}")

    name = get_in(opts, [:name])
    unless match?(<<_::binary>>, name), do: raise("required option :name is missing")

    unless Alfred.name_available?(name), do: raise("requested name is taken")

    pio = Sally.Device.pio_check(device, opts)

    final_opts = [pio: pio] ++ Keyword.take(opts, [:name, :description, :ttl_ms])

    Sally.DevAlias.create(device, final_opts)
  end

  def device_add_alias(:latest, opts) do
    ident = device_latest(opts)

    unless match?(<<_::binary>>, ident), do: raise("unable to locate a recent device")

    device_add_alias(ident, opts)
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
  def device_latest(opts \\ [schema: false, hours: -1]) do
    opts = put_in(opts, [:schema], false)

    Sally.Device.latest(opts)
  end

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
    from = opts[:from]
    unless from, do: raise("from device missing")

    to = opts[:to] || device_latest(opts)
    to = if is_nil(to) or to == :latest, do: device_latest(opts), else: to
    unless to, do: raise("to device missing (no latest)")

    Sally.Device.move_aliases(from, to)
  end

  defdelegate explain(), to: Sally.DevAlias.Explain, as: :all
  defdelegate explain(name, category, what, opts \\ []), to: Sally.DevAlias.Explain, as: :query

  defp host_if_found(<<_::binary>> = what, by \\ :name, func, return_key \\ :name)
       when is_atom(by) and is_function(func) and is_atom(return_key) do
    host = Sally.Host.find_by([{by, what}])

    if host do
      host = func.(host)

      cond do
        return_key == :struct -> host
        is_map_key(host, return_key) -> Map.get(host, return_key)
        true -> {:unknown_key, return_key}
      end
    else
      {:not_found, what}
    end
  end

  def host_devices(<<_::binary>> = name) do
    with %Sally.Host{} = host <- Sally.Host.find_by(name: name),
         %{devices: devices} <- Sally.Repo.preload(host, :devices) do
      Enum.map(devices, &Map.get(&1, :ident))
    else
      _ -> {:not_found, name}
    end
  end

  def host_info(name) do
    Sally.Host.find_by(name: name)
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
  @host_latest_defaults Sally.Host.latest_defaults() ++ [schema: false]
  def host_latest(opts \\ @host_latest_defaults), do: Sally.Host.latest(opts)

  @doc """
  Initiate an OTA for specific host name

  * `file:` the firmware file, defaults to `latest.bin`
  """
  def host_ota(<<_::binary>> = name, opts \\ []) do
    host_if_found(name, &Sally.Host.ota(&1, opts))
  end

  def host_ota_live(opts \\ []) do
    hosts = Sally.Host.live(opts)

    Enum.map(hosts, &(Sally.Host.ota(&1, opts) |> Map.get(:name)))
  end

  def host_profile(<<_::binary>> = name, <<_::binary>> = profile) do
    host_if_found(name, &Sally.Host.profile(&1, profile), :profile)
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
  def host_rename(<<_::binary>> = from, <<_::binary>> = to) do
    host_if_found(from, &Sally.Host.rename(&1, to))
  end

  @doc since: "0.7.14"
  def host_restart(<<_::binary>> = name, opts \\ []) do
    host_if_found(name, &Sally.Host.restart(&1, opts))
  end

  def host_restart_live(opts \\ []) do
    Sally.Host.live(opts)
    |> Enum.map(&(Sally.Host.restart(&1, opts) |> Map.get(:name)))
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
  def host_retire(<<_::binary>> = name) do
    host_if_found(name, &Sally.Host.retire(&1))
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
    Sally.Host.unnamed(opts) |> many_results(opts)
  end

  def host_setup(ident, opts) when is_binary(ident) and is_list(opts) do
    host_if_found(ident, :ident, &Sally.Host.setup(&1, opts), :struct)
  end

  def ttl_adjust([<<_::binary>> | _] = names, ttl_ms) when is_integer(ttl_ms) do
    Enum.map(names, &Sally.DevAlias.ttl_adjust(&1, ttl_ms))
  end

  @doc false
  @many_error_list "expected a list, got: "
  @many_error_map "expected a map or struct, got: "
  @many_error_field "field does not exist in result: "
  def many_results([], _opts), do: :none

  def many_results(what, opts) do
    multi? = Keyword.get(opts, :multiple, false)
    schema? = Keyword.get(opts, :schema, false)
    key = Keyword.get(opts, :field)

    unless is_list(what), do: raise(@many_error_list <> inspect(what))

    first = List.first(what)
    unless is_map(first), do: raise(@many_error_map <> inspect(first))
    unless is_map_key(first, key), do: raise(@many_error_field <> inspect(key))

    case what do
      [_] ->
        cond do
          schema? -> first
          true -> Map.get(first, key)
        end

      [%{} | _] ->
        cond do
          multi? and schema? -> what
          multi? -> Enum.map(what, &Map.get(&1, key))
          true -> :multiple
        end
    end
  end
end
