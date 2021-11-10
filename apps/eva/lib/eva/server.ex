defmodule Eva.Server do
  require Logger

  alias __MODULE__
  alias Alfred.{ExecCmd, ExecResult}
  alias Alfred.Notify.Memo
  alias Broom.TrackerEntry
  alias Eva.{Names, Opts, State, Variant}

  use GenServer

  @impl true
  def init(%Opts{} = opts) do
    s = State.new(opts) |> State.load_config()

    if is_struct(s.variant) and s.variant.valid? do
      # a device can only be found and registered for notifications once known
      # by Alfred (e.g. device was seen and has become a KnownName).  as such, drop into
      # a series of info messages to poll for (aka find) the devices.  this is only necessary
      # after a cold start when Alfred hasn't seen any names yet.
      {:ok, s, {:continue, :register_self}}
    else
      {:stop, s.variant}
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
  def handle_call(:equipment, _from, %State{variant: %_{mode: mode}} = s), do: mode |> reply(s)

  @impl true
  def handle_call({:status, _name, opts}, _from, %State{} = s) do
    s.variant
    |> Variant.status(opts)
    |> reply(s)
  end

  @impl true
  def handle_call(mode, _from, %State{mode: server_mode} = s)
      when mode in [:standby, :resume] and server_mode in [:ready, :standby] do
    # reused startup logic by invoking handle_continue/2
    {:reply, :ok, s, {:continue, mode}}
  end

  @impl true
  def handle_call(%ExecCmd{} = ec, _from, %State{mode: mode} = s) when mode in [:starting, :finding_names] do
    result = ExecResult.from_cmd(ec, rc: mode)

    {:reply, result, s}
  end

  @impl true
  def handle_call(%ExecCmd{cmd: cmd} = ec, _from, %State{} = s) when cmd in ["standby", "resume"] do
    mode = String.to_atom(cmd)
    result = ExecResult.from_cmd(ec, [])

    {:reply, result, s, {:continue, mode}}
  end

  @impl true
  def handle_call(%ExecCmd{} = ec, from, %State{} = s) do
    {variant, response} = s.variant |> Variant.execute(ec, from)

    variant
    |> State.update(s)
    |> reply(response)
  end

  @impl true
  # called once at start-up,
  def handle_continue(:find_names, %State{} = s), do: handle_info(:find_names, State.mode(s, :finding_names))

  @impl true
  def handle_continue(:register_self, %State{} = s) do
    s
    |> State.just_saw()
    |> noreply_continue(:find_names)
  end

  @impl true
  # called once all devices are found and registered for notifications
  def handle_continue(mode, %State{} = s) when mode in [:ready, :resume, :standby] do
    # NOTE  direct update to variant
    case mode do
      :ready -> %{s.variant | mode: mode} |> State.update(s) |> State.mode(:ready)
      x -> %{s.variant | mode: mode} |> State.update(s) |> State.mode(x)
    end
    |> noreply()
  end

  # ignore notifies while initializing or finding names
  @impl true
  def handle_info({Alfred, %Memo{}}, %State{mode: mode} = s)
      when mode in [:starting, :finding_names] do
    noreply(s)
  end

  @impl true
  def handle_info({Alfred, %Memo{} = memo}, %State{} = s) do
    s.variant
    |> Variant.handle_notify(memo, s.mode)
    |> Variant.control(memo, s.mode)
    |> State.update(s)
    |> State.just_saw()
    |> noreply()
  end

  @impl true
  def handle_info({Broom, %TrackerEntry{} = te}, %State{} = s) do
    s.variant
    |> Variant.handle_release(te)
    |> State.update(s)
    |> noreply()
  end

  @impl true
  def handle_info(:find_names, %State{variant: %_{names: names, notifies: _}} = s) do
    {names, notifies} = Names.find_and_register(names)

    # NOTE:  direct update to expected variant struct elements
    s = %{s.variant | names: names, notifies: notifies} |> State.update(s) |> State.mode(:finding_names)

    if Names.all_found?(names) do
      # good, all devices have been located, move to the initial mode
      s |> noreply_continue(s.opts.initial_mode)
    else
      # all names not found, keep looking after a delay
      server = Opts.server_name(s.opts)
      Process.send_after(server, :find_names, 1900)
      noreply(s)
    end
  end

  @impl true
  def handle_info({:instruct, instruct}, %State{} = s) do
    s.variant |> Variant.handle_instruct(instruct) |> State.update(s) |> noreply()
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
