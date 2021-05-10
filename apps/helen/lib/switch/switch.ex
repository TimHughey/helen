defmodule Switch do
  @moduledoc """
    The Switch module provides the public API for Switch devices.
  """

  require Logger
  use Timex

  alias Switch.DB.{Alias, Command, Device}
  alias Switch.{Execute, Msg, Notify, Status}

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
  defdelegate cmd_counts_reset(opts), to: Command
  defdelegate cmds_tracked, to: Command

  defdelegate delete(name_or_id), to: Alias, as: :delete
  defdelegate device_find(device_or_id), to: Device, as: :find
  defdelegate devices_begin_with(pattern \\ ""), to: Device

  # (1 of 2) single arg entry point, extract name and opts
  def execute(%{name: name} = cmd_map) do
    opts = cmd_map[:opts] || []
    cmd_map = Map.delete(cmd_map, :opts)

    execute(name, cmd_map, opts)
  end

  # (2 of 2) prevent crashes
  def execute(cmd_map) when is_map(cmd_map) do
    {:invalid, "cmd map must include name"}
  end

  # (3 of 3) name, cmd_map and opts specified as unique arguments
  # NOTE: opts can contain notify_when_released: true to enter a receive loop waiting for ack
  def execute(name, cmd_map, opts) when is_binary(name) and is_map(cmd_map) and is_list(opts) do
    # ensure the alias name is in the map
    cmd_map = Map.put_new(cmd_map, :name, name)

    # if the caller is willing to wait for the ack add notify_when_released
    opts = (opts[:wait_for_ack] && opts ++ [notify_when_released: true]) || opts

    txn_rc =
      Repo.transaction(fn ->
        res = status(name) |> Execute.execute(name, cmd_map, opts)

        Logger.debug(["\n", inspect(res, pretty: true)])

        res
      end)

    # is the caller willing to wait for the ack?
    will_wait = (opts[:wait_for_ack] && :wait_for_ack) || false

    case txn_rc do
      {:ok, {:pending, res}} when will_wait == :wait_for_ack -> wait_for_ack(res)
      {:ok, res} -> res
      error -> {:invalid, [name, " execute failed: ", inspect(error)]}
    end
  end

  @deprecated "use execute/1 or execute/2 instead"
  def execute_action(_), do: :execute_action_removed

  defdelegate exists?(name), to: Alias

  defdelegate handle_message(msg_in), to: Msg, as: :handle

  defdelegate names, to: Alias, as: :names
  defdelegate names_begin_with(patten), to: Alias, as: :names_begin_with

  defdelegate notify_as_needed(msg), to: Notify
  defdelegate notify_map, to: Notify
  defdelegate notify_register(name), to: Notify
  defdelegate notify_restart(opts \\ []), to: Notify, as: :restart
  defdelegate notify_state, to: Notify, as: :state

  def off(name, opts \\ []) when is_binary(name) do
    %{cmd: "off", name: name, opts: opts} |> execute()
  end

  def off_names_begin_with(pattern, opts \\ []) do
    names = Alias.names_begin_with(pattern)

    for name <- names do
      off(name, opts)
    end
  end

  def on(name, opts \\ []) when is_binary(name) do
    %{cmd: "on", name: name, opts: opts} |> execute()
  end

  def status(name_or_id, opts \\ []) when is_list(opts) do
    case Alias.find(name_or_id) do
      %Alias{} = a -> Status.make_status(a, opts)
      other -> other
    end
  end

  # (1 of 2) wait requested and cmd is pending
  defp wait_for_ack(res) do
    refid = res[:refid]
    name = res[:name]

    Logger.debug("waiting for ack: #{inspect(res, pretty: true)}")

    {elapsed, res} =
      :timer.tc(fn ->
        receive do
          {{Switch.Broom, :ref_released}, ^refid, :acked} -> status(name)
          {{Switch.Broom, :ref_released}, ^refid, :orphaned} -> {:failed, "cmd orphaned"}
        after
          5000 -> {:failed, "wait for ack timeout"}
        end
      end)

    put_in(res, [:ack_elapsed_us], elapsed)
  end
end
