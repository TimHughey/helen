defmodule Switch do
  @moduledoc ~S"""
  Switch

  Primary entry module for all Switch functionality.
  """

  alias Switch.DB.{Alias, Command, Device}
  alias Switch.Notify

  #
  ## Public API
  #

  @doc delegate_to: {Command, :acked?, 1}
  defdelegate acked?(refid), to: Command

  def aliases(mode \\ :print) do
    import Ecto.Query, only: [from: 2]

    cols = [{"Name", :name}, {"Status", :status}, {"Position", :position}]

    aliases =
      for %Alias{name: name} <-
            from(x in Alias, order_by: x.name) |> Repo.all() do
        {rc, position} = Switch.position(name)
        %{name: name, status: rc, position: position}
      end

    case mode do
      :print ->
        Scribe.print(aliases, data: cols)

      :browse ->
        Scribe.console(aliases, data: cols)

      :raw ->
        aliases

      :count ->
        Enum.count(aliases)
    end
  end

  @doc """
    Public API for creating a Switch Alias
  """
  @doc since: "0.0.21"
  def alias_create(device_or_id, name, pio, opts \\ []) do
    # first, find the device to alias
    with %Device{device: dev_name} = dev <- device_find(device_or_id),
         # create the alias and capture it's name
         {:ok, %Alias{name: name}} <- Alias.create(dev, name, pio, opts) do
      [created: [name: name, device: dev_name, pio: pio]]
    else
      nil -> {:not_found, device_or_id}
      error -> error
    end
  end

  @doc delegate_to: {Alias, :find, 1}
  @doc since: "0.0.21"
  defdelegate alias_find(name_or_id), to: Alias, as: :find

  @doc """
  Rename a switch alias and/or update description and ttl_ms

      Optional opts:
      description: <binary>   -- new description
      ttl_ms:      <integer>  -- new ttl_ms
  """
  @doc since: "0.0.23"
  def alias_rename(name_or_id, new_name, opts \\ []) do
    Alias.rename(name_or_id, new_name, opts)
  end

  @doc delegate_to: {Command, :cmds_count, 0}
  @doc since: "0.0.24"
  defdelegate cmd_counts, to: Command

  @doc delegate_to: {Command, :cmd_counts_reset, 1}
  @doc since: "0.0.24"
  defdelegate cmd_counts_reset(opts \\ []), to: Command

  @doc delegate_to: {Command, :cmds_tracked, 0}
  @doc since: "0.0.24"
  defdelegate cmds_tracked, to: Command

  @doc delegate_to: {Alias, :delete, 1}
  @doc since: "0.0.21"
  defdelegate delete(name_or_id), to: Alias, as: :delete

  @doc """
    Generic execute for general purpose use

    ```elixir
      # general purpose use
      Switch.execute(%{cmd: :on, name: "device alias"})

    ```

  """
  @doc since: "0.9.9"
  def execute(%{cmd: cmd, name: name} = action) do
    opts = action[:opts] || []

    case cmd do
      :on -> on(name, opts)
      :off -> off(name, opts)
      _cmd -> :invalid_action
    end
  end

  @doc """
    Execute an action

    ```elixir
      # direct support for Helen Worker actions
      Switch.execute_action(%{worker_cmd: :on, worker: %{name: "device alias"}})
    ```

  """
  @doc since: "0.0.27"
  def execute_action(%{worker_cmd: cmd, worker: %{name: name}}),
    do: execute(%{cmd: cmd, name: name})

  @doc delegate_to: {Alias, :exists?, 1}
  @doc since: "0.0.27"
  defdelegate exists?(name_or_id), to: Alias, as: :exists?

  @doc delegate_to: {Alias, :news, 1}
  @doc since: "0.0.22"
  defdelegate names, to: Alias, as: :names

  @doc delegate_to: {Alias, :names_begin_with, 1}
  @doc since: "0.0.22"
  defdelegate names_begin_with(patten), to: Alias, as: :names_begin_with

  @doc delegate_to: {Notify, :notify_as_needed, 1}
  @doc since: "0.0.26"
  defdelegate notify_as_needed(msg), to: Notify

  @doc delegate_to: {Notify, :notify_register, 1}
  @doc since: "0.0.26"
  defdelegate notify_register(name), to: Notify

  @doc delegate_to: {Notify, :notify_map, 0}
  @doc since: "0.0.27"
  defdelegate notify_map, to: Notify

  @doc delegate_to: {Device, :find, 1}
  @doc since: "0.0.21"
  defdelegate device_find(device_or_id), to: Device, as: :find

  @doc """
    Find a the alias of a Device using pio
  """
  @doc since: "0.0.21"
  def device_find_alias(device_or_id, name, pio, opts \\ []) do
    case device_find(device_or_id) do
      %Device{} = dev -> Device.find_alias(dev, name, pio, opts)
      _not_found -> {:not_found, device_or_id}
    end
  end

  defdelegate devices_begin_with(pattern \\ ""), to: Device

  defdelegate handle_message(msg), to: Switch.Msg, as: :handle

  @doc """
  Convenience wrapper of Switch.position/1

  Takes a switch name or id.

  Returns a binary on success.  Tuple on failure.
  """
  @doc since: "0.0.27"
  def now(name_or_id), do: Switch.position(name_or_id)

  @doc delegate_to: {Alias, :on, 1}
  defdelegate on(name_or_id), to: Alias

  @doc delegate_to: {Alias, :on, 2}
  defdelegate on(name_or_id, opts), to: Alias

  @doc delegate_to: {Alias, :off, 1}
  defdelegate off(name_or_id), to: Alias

  @doc delegate_to: {Alias, :off, 2}
  defdelegate off(name_or_id, opts), to: Alias

  @doc delegate_to: {Alias, :off_names_begin_with, 1}
  defdelegate off_names_begin_with(pattern), to: Alias

  @doc delegate_to: {Alias, :off_names_begin_with, 2}
  defdelegate off_names_begin_with(pattern, opts), to: Alias

  @doc """
    Set the position (state) of a Switch PIO using it's Alias

    opts:
      position: true | false
          true = switch state set to on
          false = switch state set to off

      ensure: true | false
          true = checks the switch position prior to setting
                 if the current position does not match the new position
                 then lazy: false is appened to the opts

      lazy: true | false
          true = if the requested position matches the database position
                 then do nothing to avoid redundant commands to remotes
          false = always send the position command
  """
  def position(name, opts \\ []) when is_binary(name) and is_list(opts) do
    case opts[:ensure] || false do
      true -> position_ensure(name, opts)
      false -> Alias.position(name, opts)
    end
  end

  defp position_ensure(name, opts) do
    pos_wanted = Keyword.get(opts, :position)
    {rc, pos_current} = sw_rc = Alias.position(name)

    with {:switch, :ok} <- {:switch, rc},
         {:ensure, true} <- {:ensure, pos_wanted == pos_current} do
      # position is correct, return it
      sw_rc
    else
      # there was a problem with the switch, return
      {:switch, _error} ->
        sw_rc

      # switch does not match desired position, force it
      {:ensure, false} ->
        # force the position change
        opts = Keyword.put(opts, :lazy, false)
        Alias.position(name, opts)
    end
  end

  @doc """
  Rename a switch alias and/or update description and ttl_ms
    (alias for Switch.alias_rename)

      Optional opts:
      description: <binary>   -- new description
      ttl_ms:      <integer>  -- new ttl_ms
  """
  @doc since: "0.0.23"
  def rename(name_or_id, new_name, opts \\ []) do
    Alias.rename(name_or_id, new_name, opts)
  end

  @doc delegate_to: {Notify, :restart, 1}
  @doc since: "0.0.27"
  defdelegate restart(opts \\ []), to: Notify

  @doc delegate_to: {Notify, :state, 0}
  @doc since: "0.0.26"
  defdelegate state, to: Notify

  @doc """
    Get a map representing the status of the Switch

  """
  @doc since: "0.9.9"
  def status(name_or_id) do
    base = %{name: name_or_id}

    pos_to_atom = fn x -> if x, do: :on, else: :off end
    put_pos = fn pos -> put_in(base, [:cmd], pos_to_atom.(pos)) end
    put_extra = fn m, [{k, v}] -> put_in(m, [k], v) end

    case position(name_or_id) do
      {:ok, pos} when is_boolean(pos) -> put_pos.(pos)
      {:ttl_expired, pos} -> put_pos.(pos) |> put_extra.(ttl_expired: true)
      {:pending, res} -> put_pos.(res[:position]) |> put_extra.(pending: true)
      error -> put_extra.(base, error: error)
    end
  end

  @doc delegate_to: {Alias, :toggle, 1}
  defdelegate toggle(name_or_id), to: Alias

  @doc delegate_to: {Alias, :toggle, 2}
  defdelegate toggle(name_or_id, opts), to: Alias
end
