defmodule Switch do
  @moduledoc ~S"""
  Switch

  Primary entry module for all Switch functionality.
  """

  alias Switch.DB.{Alias, Command, Device}
  alias Switch.{Execute, Msg, Notify, Status}

  #
  ## Public API
  #

  defdelegate acked?(refid), to: Command

  def alias_create(device_or_id, name, pio, opts \\ []) do
    # first, find the device to alias
    with %Device{} = d <- device_find(device_or_id),
         {:exists?, nil, _} <- {:exists?, Device.find_alias(d, pio), d},
         # create the alias and capture it's name
         {:ok, %Alias{} = a} <- Alias.create(d, name, pio, opts) do
      [created: [name: a.name, device: d.device, pio: pio]]
    else
      {:exists?, %Alias{} = a, %Device{} = d} -> [exists: [name: a.name, device: d.device, pio: pio]]
      nil -> {:not_found, device_or_id}
      error -> error
    end
  end

  defdelegate alias_find(name_or_id), to: Alias, as: :find
  defdelegate cmd_counts, to: Command
  defdelegate cmd_counts_reset(opts \\ []), to: Command
  defdelegate cmds_tracked, to: Command

  defdelegate delete(name_or_id), to: Alias, as: :delete
  defdelegate device_find(device_or_id), to: Device, as: :find
  defdelegate devices_begin_with(pattern \\ ""), to: Device

  defdelegate execute(cmd), to: Execute
  defdelegate execute(cmd, opts), to: Execute

  @deprecated "Use execute/2 instead"
  def execute_action(%{worker_cmd: cmd, worker: %{name: name}}),
    do: execute(%{cmd: cmd, name: name})

  defdelegate exists?(name_or_id), to: Alias, as: :exists?

  defdelegate handle_message(msg), to: Msg, as: :handle

  defdelegate names, to: Alias, as: :names
  defdelegate names_begin_with(patten), to: Alias, as: :names_begin_with

  defdelegate notify_as_needed(msg), to: Notify
  defdelegate notify_register(name), to: Notify
  defdelegate notify_map, to: Notify

  def off(name, opts \\ []) when is_binary(name) do
    %{cmd: :off, name: name} |> execute(opts)
  end

  def off_names_begin_with(pattern, opts \\ []) do
    names = Alias.names_begin_with(pattern)

    for name <- names do
      off(name, opts)
    end
  end

  def on(name, opts \\ []) when is_binary(name) do
    %{cmd: :on, name: name} |> execute(opts)
  end

  @deprecated "Use execute/2 instead"
  def position(_name, _opts \\ []), do: :position_removed
  #   case opts[:ensure] || false do
  #     true -> position_ensure(name, opts)
  #     false -> Alias.position(name, opts)
  #   end
  # end

  # defp position_ensure(name, opts) do
  #   pos_wanted = Keyword.get(opts, :position)
  #   {rc, pos_current} = sw_rc = Alias.position(name)
  #
  #   with {:switch, :ok} <- {:switch, rc},
  #        {:ensure, true} <- {:ensure, pos_wanted == pos_current} do
  #     # position is correct, return it
  #     sw_rc
  #   else
  #     # there was a problem with the switch, return
  #     {:switch, _error} ->
  #       sw_rc
  #
  #     # switch does not match desired position, force it
  #     {:ensure, false} ->
  #       # force the position change
  #       opts = Keyword.put(opts, :lazy, false)
  #       Alias.position(name, opts)
  #   end
  # end

  defdelegate restart(opts \\ []), to: Notify
  defdelegate state, to: Notify

  def status(name_or_id, opts \\ []) when is_list(opts) do
    import Alias, only: [find: 1]
    import Status, only: [make_status: 2]

    case find(name_or_id) do
      %Alias{} = a -> make_status(a, opts)
      other -> other
    end
  end

  @deprecated "Use execute/2 instead"
  def toggle(_name_or_id), do: :toggle_removed

  @deprecated "Use execute/2 instead"
  def toggle(_name_or_id, _opts), do: :toggle_removed
end
