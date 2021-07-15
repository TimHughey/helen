defmodule Eva.Server do
  require Logger

  alias __MODULE__
  alias Alfred.NotifyMemo, as: Memo
  alias Broom.TrackerEntry
  alias Eva.{Opts, State, Variant}

  use GenServer

  @impl true
  def init(%Opts{} = opts) do
    s = State.new(opts) |> State.load_config()

    if s.variant.valid? do
      # a device can only be found and registered for notifications once known
      # by Alfred (e.g. device was seen and has become a KnownName).  as such, drop into
      # a series of info messages to poll for (aka find) the devices.  this is only necessary
      # after a cold start when Alfred hasn't seen any names yet.
      {:ok, s, {:continue, :find_devs}}
    else
      {:stop, s.variant.invalid_reason}
    end
  end

  def start_link(%Opts{} = opts) do
    # assemble the genserver opts
    genserver_opts = [name: opts.server.name] ++ opts.server.genserver
    GenServer.start_link(Server, opts, genserver_opts)
  end

  @impl true
  def handle_call(:current_mode, _from, %State{} = s), do: s.mode |> reply(s)

  @impl true
  def handle_call(:equipment, _from, %State{} = s), do: Variant.current_mode(s.variant) |> reply(s)

  @impl true
  def handle_call(mode, _from, %State{} = s) when mode in [:standby, :resume] do
    # reused startup logic by invoking handle_continue/2
    {:reply, :ok, s, {:continue, mode}}
  end

  @impl true
  # called once at start-up,
  def handle_continue(:find_devs, %State{} = s), do: handle_info(:find_devs, s)

  @impl true
  # called once all devices are found and registered for notifications
  def handle_continue(mode, %State{} = s) when mode in [:ready, :resume, :standby] do
    case mode do
      x when x in [:ready, :resume] ->
        State.mode(s, :ready)

      :standby ->
        s.variant |> Variant.mode(:standby) |> State.update_variant(s) |> State.mode(:standby)
    end
    |> noreply()
  end

  @impl true
  def handle_info({Alfred, :notify, %Memo{} = memo}, %State{} = s) do
    s.variant
    |> Variant.handle_notify(memo, s.mode)
    |> Variant.control(memo, s.mode)
    |> State.update_variant(s)
    |> noreply()
  end

  @impl true
  def handle_info({Broom, :release, %TrackerEntry{} = te}, %State{} = s) do
    s.variant
    |> Variant.handle_release(te)
    |> State.update_variant(s)
    |> noreply()
  end

  @impl true
  # called repeatedly until all devices are found
  # it is possble this is only called once if Alfred already knows the devices required
  def handle_info(:find_devs, %State{} = s) do
    s = Variant.find_devices(s.variant) |> State.update_variant(s)

    if Variant.found_all_devs?(s.variant) do
      # good, all devices have been located, move to the initial mode
      s |> noreply_continue(s.opts.initial_mode)
    else
      server = Opts.server_name(s.opts)
      Process.send_after(server, :find_devs, 1900)
      noreply(s)
    end
  end

  ##
  ## GenServer Reply Helpers
  ##

  defp noreply(%State{} = s), do: {:noreply, s}
  defp noreply_continue(%State{} = s, term), do: {:noreply, s, {:continue, term}}

  defp reply(%State{} = s, val), do: {:reply, val, s}
  defp reply(val, %State{} = s), do: {:reply, val, s}
  # defp reply({%State{} = s, val}), do: {:reply, val, s}
  # defp reply_ok(%State{} = s), do: {:ok, s}
end
