defmodule Switch do
  @moduledoc ~S"""
  Switch

  Primary entry module for all Switch functionality.
  """

  require Logger

  alias Switch.DB.Alias, as: Alias
  alias Switch.DB.Device, as: Device

  #
  ## Public API
  #

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

      true ->
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

  @doc """
    Public API for deleting a Switch Alias
  """
  @doc since: "0.0.21"
  defdelegate delete(name_or_id), to: Alias, as: :delete

  @doc """
  Finds a Switch Alias by name or id

  opts are passed as-is to Repo.preload/2
  """

  @doc since: "0.0.21"
  defdelegate alias_find(name_or_id), to: Alias, as: :find

  @doc """
    Retrieve a list of alias names
  """
  @doc since: "0.0.22"
  defdelegate names, to: Alias, as: :names

  @doc """
    Retrieve a list of alias names that begin with a pattern
  """
  @doc since: "0.0.22"
  defdelegate names_begin_with(patten), to: Alias, as: :names_begin_with

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

  @doc """
    Find a Switch Device by device or id
  """
  @doc since: "0.0.21"
  defdelegate device_find(device_or_id), to: Device, as: :find

  @doc """
    Find a the alias of a Device using pio
  """
  @doc since: "0.0.21"
  def device_find_alias(device_or_id, name, pio, opts \\ []) do
    with %Device{} = dev <- device_find(device_or_id) do
      Device.find_alias(dev, name, pio, opts)
    else
      _not_found -> {:not_found, device_or_id}
    end
  end

  @doc """
    Retrieve a list of devices that begin with a pattern
  """
  @doc since: "0.0.21"
  def devices_begin_with(pattern) when is_binary(pattern) do
    import Ecto.Query, only: [from: 2]

    like_string = [pattern, "%"] |> IO.iodata_to_binary()

    from(x in Device,
      where: like(x.device, ^like_string),
      order_by: x.device,
      select: x.device
    )
    |> Repo.all()
  end

  @doc """
    Handles all aspects of processing messages for Sensors

     - if the message hasn't been processed, then attempt to
  """
  @doc since: "0.0.21"
  def handle_message(%{processed: false, type: "switch"} = msg_in) do
    # the with begins with processing the message through DB.Device.upsert/1
    with %{switch_device: switch_device} = msg <- Device.upsert(msg_in),
         # was the upset a success?
         {:ok, %Device{}} <- switch_device,
         # technically the message has been processed at this point
         msg <- Map.put(msg, :processed, true),
         # Switch does not write any data to the timeseries database
         # (unlike Sensor, Remote) so simulate the write_rc success
         # now send the augmented message to the timeseries database
         msg <- Map.put(msg, :write_rc, {:processed, :ok}) do
      msg
    else
      # if there was an error, add fault: <device_fault> to the message and
      # the corresponding <device_fault>: <error> to signal to downstream
      # functions there was an issue
      error ->
        Map.merge(msg_in, %{
          processed: true,
          fault: :switch_fault,
          switch_fault: error
        })
    end
  end

  # if the primary handle_message does not match then simply return the msg
  # since it wasn't for switch and/or has already been processed in the
  # pipeline
  def handle_message(%{} = msg_in), do: msg_in

  def on(name_or_id, opts \\ []), do: Alias.on(name_or_id, opts)

  def off(name_id_or_list, opts \\ []), do: Alias.off(name_id_or_list, opts)

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
    ensure = Keyword.get(opts, :ensure, false)

    case ensure do
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

  def toggle(name_or_id, opts \\ []), do: Alias.toggle(name_or_id, opts)
end
