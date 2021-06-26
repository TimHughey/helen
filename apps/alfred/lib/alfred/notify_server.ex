defmodule Alfred.NotifyTo do
  defstruct name: "none",
            pid: nil,
            ref: nil,
            last_notify: DateTime.from_unix!(0),
            interval_ms: 60_000

  @type t :: %__MODULE__{
          name: String.t(),
          pid: pid(),
          ref: reference(),
          last_notify: DateTime.t(),
          interval_ms: pos_integer()
        }

  def new(name, opts) do
    %__MODULE__{name: name, pid: opts[:pid], ref: make_ref(), interval_ms: opts[:interval_ms]}
  end
end

defmodule Alfred.NotifyMemo do
  alias Alfred.{KnownName, NotifyTo}
  defstruct name: "unknown", ref: nil, pid: nil, seen_at: nil, missing?: true

  @type t :: %__MODULE__{
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

defmodule Alfred.Notify.Server do
  defmodule State do
    alias Alfred.{KnownName, NotifyTo}
    defstruct registrations: %{}, started_at: nil

    @type monitor_ref() :: reference()
    @type name() :: String.t()
    @type notify_pid() :: pid()
    @type registration_key() :: {String.t(), notify_pid(), monitor_ref()}
    @type t :: %__MODULE__{
            registrations: %{optional(registration_key()) => KnownName.t()},
            started_at: DateTime.t()
          }

    def register(%KnownName{} = kn, opts, %State{registrations: regs} = s) do
      nt = NotifyTo.new(kn.name, opts)

      # only link if requested
      if opts[:link], do: Process.link(nt.pid)

      key = make_registration_key(nt)

      s = %State{s | registrations: put_in(regs, [key], nt)}

      {s, {:ok, nt}}
    end

    def unregister(ref, %State{registrations: regs} = s) do
      for {{_, _, mon_ref} = reg_key, nt} <- s.registrations, nt.ref == ref, reduce: %State{} do
        %State{} = s ->
          Process.demonitor(mon_ref, [:flush])
          Process.unlink(nt.pid)

          %State{s | registrations: Map.delete(regs, reg_key)}
      end
    end

    def make_registration_key(%NotifyTo{} = nt), do: {nt.name, nt.pid, Process.monitor(nt.pid)}
    def new, do: %State{started_at: DateTime.utc_now()}
  end

  ##
  ## Alfred Notify Server
  ##

  use GenServer, shutdown: 2000

  require Logger

  alias Alfred.{KnownName, NotifyMemo, NotifyTo}
  alias Alfred.Notify.Server, as: Mod

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
    interval_ms = if opts[:interval_ms] == :use_ttl, do: kn.ttl_ms, else: opts[:interval_ms]
    opts = [interval_ms: interval_ms, pid: pid] ++ Keyword.delete_first(opts, :interval_ms)
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
    for {{name, pid, _monitor_ref}, nt} <- s.registrations, name == kn.name do
      utc_now = DateTime.utc_now()
      next_notify = DateTime.add(nt.last_notify, nt.interval_ms, :millisecond)

      if DateTime.compare(utc_now, next_notify) in [:eq, :gt] do
        Process.send(pid, {Alfred, :notify, NotifyMemo.new(nt, kn)}, [])
      end
    end

    noreply(s)
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, %State{registrations: regs} = s) do
    Logger.debug("#{inspect(pid)} exited, removing notify registration(s)")

    # remove the registration
    for {reg_key, _nt} <- regs, elem(reg_key, 3) == ref, reduce: %State{} do
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
