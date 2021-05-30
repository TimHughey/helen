defmodule PulseWidth do
  @moduledoc """
    The PulseWidth module provides the public API for PulseWidth devices.
  """

  require Logger
  use Timex

  alias PulseWidth.DB.{Alias, Device}
  alias PulseWidth.{Execute, Msg, Status}

  @behaviour Alfred.Mutable

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

  defdelegate delete(name_or_id), to: Alias, as: :delete
  defdelegate device_find(device_or_id), to: Device, as: :find
  defdelegate devices_begin_with(pattern \\ ""), to: Device

  # Execute a command map
  # NOTE: opts can contain notify_when_released: true to enter a receive loop waiting for ack
  # (1 of 2) cmd map and all_opts are separate arguments
  @impl true
  defdelegate execute(cmd_map), to: Execute

  @impl true
  # (2 of 2) name, cmd_map and opts specified as unique arguments
  defdelegate execute(alias_name, cmd_map, all_opts), to: Execute

  @impl true
  defdelegate exists?(name), to: Alias

  def handle_message(msg_in) do
    msg_in |> put_in([:msg_handler], __MODULE__) |> Msg.handle() |> Alfred.just_saw()
  end

  defdelegate names, to: Alias, as: :names
  defdelegate names_begin_with(patten), to: Alias, as: :names_begin_with

  @impl true
  def off(name, opts \\ []) when is_binary(name) do
    %{cmd: "off", name: name, opts: opts} |> execute()
  end

  def off_names_begin_with(pattern, opts \\ []) do
    names = Alias.names_begin_with(pattern)

    for name <- names do
      off(name, opts)
    end
  end

  @impl true
  def on(name, opts \\ []) when is_binary(name) do
    %{cmd: "on", name: name, opts: opts} |> execute()
  end

  @impl true
  def status(name_or_id, opts \\ []) when is_list(opts) do
    case Alias.find(name_or_id) do
      %Alias{} = a -> Status.make_status(a, opts)
      other -> other
    end
  end

  def track_stats, do: Execute.track_stats(:get, [])
  def track_stats_reset(keys), do: Execute.track_stats(:reset, keys)

  ##
  ## Private
  ##

  # defp make_execute_opts(opts) do
  #   {will_wait, rest} = Keyword.pop(opts, :wait_for_ack, false)
  #
  #   # if the caller is willing to wait for the ack add notify_when_released
  #   revised_opts = if will_wait, do: rest ++ [notify_when_released: true], else: rest
  #
  #   will_wait = if will_wait, do: :wait_for_ack, else: false
  #
  #   {will_wait, revised_opts}
  # end
  #
  # # (1 of 2) wait requested and cmd is pending
  # defp wait_for_ack(res) do
  #   alias Broom.TrackerEntry
  #
  #   refid = res[:refid]
  #   name = res[:name]
  #
  #   Logger.info("waiting for ack: #{inspect(res, pretty: true)}")
  #
  #   {elapsed, res} =
  #     :timer.tc(fn ->
  #       receive do
  #         {Broom, :release, %TrackerEntry{refid: ^refid, acked: true, orphaned: false}} -> status(name)
  #         {Broom, :release, %TrackerEntry{refid: ^refid, orphaned: true}} -> {:failed, "cmd orphaned"}
  #       after
  #         5000 -> {:failed, "wait for ack timeout"}
  #       end
  #     end)
  #
  #   put_in(res, [:ack_elapsed_us], elapsed)
  # end
end
