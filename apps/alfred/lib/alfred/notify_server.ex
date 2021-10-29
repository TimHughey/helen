defmodule Alfred.NotifyTo do
  alias __MODULE__
  alias Alfred.{KnownName, NotifyMemo}

  defstruct name: "none",
            pid: nil,
            ref: nil,
            monitor_ref: nil,
            last_notify: DateTime.from_unix!(0),
            interval_ms: 60_000,
            missing_ms: 60_100,
            missing_timer: nil

  @type t :: %NotifyTo{
          name: String.t(),
          pid: pid(),
          ref: reference(),
          monitor_ref: reference(),
          last_notify: DateTime.t(),
          interval_ms: pos_integer(),
          missing_ms: pos_integer(),
          missing_timer: reference()
        }

  def new(%Alfred.KnownName{} = kn, opts) do
    %NotifyTo{
      name: kn.name,
      pid: opts[:pid],
      ref: make_ref(),
      monitor_ref: opts[:monitor_ref],
      interval_ms: make_notify_interval(opts, kn.ttl_ms),
      missing_ms: kn.ttl_ms + 1000
    }
  end

  def notify(%NotifyTo{} = nt, %KnownName{} = kn) do
    utc_now = DateTime.utc_now()
    next_notify = DateTime.add(nt.last_notify, nt.interval_ms, :millisecond)

    case DateTime.compare(utc_now, next_notify) do
      x when x in [:eq, :gt] ->
        Process.send(nt.pid, {Alfred, :notify, NotifyMemo.new(nt, kn)}, [])

        %NotifyTo{nt | last_notify: DateTime.utc_now()} |> schedule_missing()

      _ ->
        nt
    end
  end

  def schedule_missing(%NotifyTo{} = nt) do
    if is_reference(nt.missing_timer), do: Process.cancel_timer(nt.missing_timer)

    %NotifyTo{nt | missing_timer: Process.send_after(self(), {:missing, nt}, nt.missing_ms)}
  end

  defp make_notify_interval(opts, ttl_ms) do
    case opts[:frequency] do
      :all -> 0
      :use_ttl -> ttl_ms
      [interval_ms: x] when is_integer(x) -> x
      _x -> ttl_ms
    end
  end
end

defmodule Alfred.NotifyMemo do
  alias __MODULE__
  alias Alfred.{KnownName, NotifyTo}

  defstruct name: "unknown", ref: nil, pid: nil, seen_at: nil, missing?: true

  @type t :: %NotifyMemo{
          name: String.t(),
          ref: reference(),
          pid: pid(),
          seen_at: DateTime.t(),
          missing?: false
        }

  def new(%NotifyTo{} = nt, %KnownName{} = kn) do
    %__MODULE__{name: kn.name, pid: nt.pid, ref: nt.ref, seen_at: kn.seen_at, missing?: kn.missing?}
  end
end

defmodule Alfred.Notify.Server.State do
  alias __MODULE__
  alias Alfred.{KnownName, NotifyTo}

  defstruct registrations: %{}, started_at: nil

  @type monitor_ref() :: reference()
  @type name() :: String.t()
  @type notify_pid() :: pid()
  @type registration_key() :: {String.t(), notify_pid(), monitor_ref()}
  @type t :: %State{
          registrations: %{optional(registration_key()) => KnownName.t()},
          started_at: DateTime.t()
        }

  def register(%KnownName{} = kn, opts, %State{} = s) do
    pid = opts[:pid]

    # only link if requested but always monitor
    if opts[:link], do: Process.link(pid)
    monitor_ref = Process.monitor(pid)

    nt = NotifyTo.new(kn, [monitor_ref: monitor_ref] ++ opts)

    {update(nt, s), {:ok, nt}}
  end

  def unregister(ref, %State{registrations: regs} = s) do
    for {{_, _, mon_ref} = reg_key, nt} <- s.registrations, nt.ref == ref, reduce: %State{} do
      %State{} = s ->
        Process.demonitor(mon_ref, [:flush])
        Process.unlink(nt.pid)

        %State{s | registrations: Map.delete(regs, reg_key)}
    end
  end

  def make_registration_key(%NotifyTo{} = nt), do: {nt.name, nt.pid, nt.monitor_ref}
  def new, do: %State{started_at: DateTime.utc_now()}

  def update(%NotifyTo{} = nt, %State{registrations: regs} = s) do
    %State{s | registrations: put_in(regs, [make_registration_key(nt)], nt)}
  end
end

defmodule Alfred.Notify.Server do
  use GenServer, shutdown: 2000

  require Logger

  alias Alfred.{KnownName, NotifyTo}
  alias Alfred.Notify.Server, as: Mod
  alias Alfred.Notify.Server.State

  @impl true
  def init(_args) do
    State.new() |> reply_ok()
  end

  def start_link(_opts) do
    Logger.debug(["starting ", inspect(Mod)])
    GenServer.start_link(__MODULE__, [], name: Mod)
  end

  @impl true
  def handle_call({:register, %KnownName{} = kn, opts}, {pid, _ref}, %State{} = s) do
    opts = Keyword.put_new(opts, :pid, pid)
    State.register(kn, opts, s) |> reply()
  end

  @impl true
  def handle_call({:registrations}, _from, %State{} = s) do
    Map.keys(s.registrations) |> reply(s)
  end

  @impl true
  def handle_call({:unregister, ref}, _from, %State{} = s) do
    State.unregister(ref, %State{} = s) |> reply(:ok)
  end

  @impl true
  def handle_cast({:just_saw, %KnownName{} = kn}, %State{} = s) do
    for {{name, _pid, _monitor_ref}, nt} <- s.registrations, name == kn.name, reduce: s do
      %State{} = s ->
        NotifyTo.notify(nt, kn) |> State.update(s)
    end
    |> noreply()
  end

  @impl true
  def handle_info({:missing, %NotifyTo{} = nt}, %State{} = s) do
    Logger.debug("MISSING\n#{inspect(nt, pretty: true)}")

    Betty.app_error(__MODULE__, name: nt.name, missing: true)

    nt |> NotifyTo.schedule_missing() |> State.update(s) |> noreply()
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, %State{registrations: regs} = s) do
    Logger.debug("#{inspect(pid)} exited, removing notify registration(s)")

    # remove the registration
    for {reg_key, _nt} <- regs, elem(reg_key, 2) == ref, reduce: %State{} do
      %State{} -> %State{s | registrations: Map.delete(regs, reg_key)}
    end
    |> noreply()
  end

  ##
  ## GenServer Reply Helpers
  ##

  defp noreply(%State{} = s), do: {:noreply, s}
  defp reply(%State{} = s, val), do: {:reply, val, s}
  defp reply(val, %State{} = s), do: {:reply, val, s}
  defp reply({%State{} = s, val}), do: {:reply, val, s}
  defp reply_ok(%State{} = s), do: {:ok, s}
end
