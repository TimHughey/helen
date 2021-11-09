defmodule Alfred.NotifyTo do
  alias __MODULE__
  alias Alfred.NotifyMemo

  defstruct name: "none",
            pid: nil,
            ref: nil,
            monitor_ref: nil,
            last_notify: DateTime.from_unix!(0),
            ttl_ms: 0,
            interval_ms: 60_000,
            missing_ms: 60_100,
            missing_timer: nil

  @type t :: %NotifyTo{
          name: String.t(),
          pid: pid(),
          ref: reference(),
          monitor_ref: reference(),
          last_notify: DateTime.t(),
          ttl_ms: pos_integer() | 0,
          interval_ms: pos_integer(),
          missing_ms: pos_integer(),
          missing_timer: reference()
        }

  def new(opts) when is_list(opts) do
    %NotifyTo{
      name: opts[:name],
      pid: opts[:pid],
      ref: make_ref(),
      monitor_ref: opts[:monitor_ref],
      ttl_ms: opts[:ttl_ms] || 0,
      interval_ms: make_notify_interval(opts),
      missing_ms: make_missing_interval(opts)
    }
  end

  def notify(%NotifyTo{} = nt, opts) do
    utc_now = DateTime.utc_now()
    next_notify = DateTime.add(nt.last_notify, nt.interval_ms, :millisecond)

    # capture ttl_ms from opts (if provided) to handle when a name is
    # registered before being seen
    ttl_ms = opts[:ttl_ms] || nt.ttl_ms
    missing_ms = nt.missing_ms

    nt = %NotifyTo{
      nt
      | ttl_ms: ttl_ms,
        missing_ms: make_missing_interval(missing_ms: missing_ms, ttl_ms: ttl_ms)
    }

    case DateTime.compare(utc_now, next_notify) do
      x when x in [:eq, :gt] ->
        Process.send(nt.pid, {Alfred, NotifyMemo.new(nt, opts)}, [])

        %NotifyTo{nt | last_notify: DateTime.utc_now()} |> schedule_missing()

      _ ->
        nt
    end
  end

  def schedule_missing(%NotifyTo{} = nt) do
    unschedule_missing(nt)

    %NotifyTo{nt | missing_timer: Process.send_after(self(), {:missing, nt}, nt.missing_ms)}
  end

  def unschedule_missing(%NotifyTo{} = nt) do
    if is_reference(nt.missing_timer), do: Process.cancel_timer(nt.missing_timer)

    %NotifyTo{nt | missing_timer: nil}
  end

  defp make_missing_interval(opts) when is_list(opts) do
    missing_ms = opts[:missing_ms] || 60_000
    ttl_ms = opts[:ttl_ms]

    # NOTE: missing_ms controls the missing timer
    #       ttl_ms is unavailable when names are registered before they are known (e.g. at startup)
    #       missing_ms should always be set to ttl_ms when it is known

    cond do
      # when ttl_ms is unavailable always use missing ms
      is_nil(ttl_ms) and is_integer(missing_ms) -> missing_ms
      # when ttl_ms is available always use it
      is_integer(ttl_ms) -> ttl_ms
      # when all else fails default to one minute
      true -> 60_000
    end
  end

  defp make_notify_interval(opts) do
    case opts[:frequency] do
      :all -> 0
      [interval_ms: x] when is_integer(x) -> x
      _x -> 60_000
    end
  end
end

defmodule Alfred.NotifyMemo do
  alias __MODULE__
  alias Alfred.NotifyTo

  defstruct name: "unknown", ref: nil, pid: nil, seen_at: nil, missing?: true

  @type t :: %NotifyMemo{
          name: String.t(),
          ref: reference(),
          pid: pid(),
          seen_at: DateTime.t(),
          missing?: boolean()
        }

  def new(%NotifyTo{} = nt, opts) do
    %NotifyMemo{
      name: opts[:name],
      pid: nt.pid,
      ref: nt.ref,
      seen_at: opts[:seen_at],
      missing?: opts[:missing?]
    }
  end
end

defmodule Alfred.Notify.Registration.Key do
  alias __MODULE__

  defstruct name: nil, notify_pid: nil, ref: nil

  @type t :: %Key{
          name: String.t(),
          notify_pid: pid(),
          ref: reference()
        }
end

defmodule Alfred.Notify.Server.State do
  alias __MODULE__
  alias Alfred.Notify.Registration.Key
  alias Alfred.NotifyTo

  defstruct registrations: %{}, started_at: nil

  @type t :: %State{
          registrations: %{optional(Key.t()) => NotifyTo.t()},
          started_at: DateTime.t()
        }

  def new, do: %State{started_at: DateTime.utc_now()}

  def notify(opts, %State{} = s) do
    name = opts[:name]

    for {%Key{name: ^name}, %NotifyTo{} = nt} <- s.registrations, reduce: s do
      %State{} = s ->
        NotifyTo.notify(nt, opts) |> State.save_notify_to(s)
    end
  end

  def register(opts, %State{} = s) when is_list(opts) do
    pid = opts[:pid]

    if Process.alive?(pid) do
      # only link if requested but always monitor
      if opts[:link], do: Process.link(pid)
      monitor_ref = Process.monitor(pid)

      notify_opts = [monitor_ref: monitor_ref] ++ opts
      nt = NotifyTo.new(notify_opts) |> NotifyTo.schedule_missing()

      {State.save_notify_to(nt, s), {:ok, nt}}
    else
      {s, {:failed, :no_process_for_pid}}
    end
  end

  def registrations(opts, %State{} = s) do
    all = opts[:all]
    name = opts[:name]

    for {%Key{} = key, %NotifyTo{} = nt} <- s.registrations, reduce: [] do
      acc ->
        cond do
          all -> [nt, acc] |> List.flatten()
          is_binary(name) and key.name == name -> [nt, acc] |> List.flatten()
          true -> acc
        end
    end
  end

  def save_notify_to(%NotifyTo{} = nt, %State{} = s) do
    key = %Key{name: nt.name, notify_pid: nt.pid, ref: nt.ref}

    %State{s | registrations: put_in(s.registrations, [key], nt)}
  end

  def unregister(ref, %State{} = s) do
    for {%Key{ref: ^ref} = key, nt} <- s.registrations, reduce: %State{} do
      acc ->
        NotifyTo.unschedule_missing(nt)

        Process.demonitor(nt.monitor_ref, [:flush])
        Process.unlink(key.notify_pid)

        %State{s | registrations: Map.delete(acc.registrations, key)}
    end
  end
end

defmodule Alfred.Notify.Server do
  use GenServer, shutdown: 2000

  require Logger

  alias Alfred.Notify.Server, as: Mod
  alias Alfred.Notify.Server.State
  alias Alfred.NotifyTo

  @impl true
  def init(_args) do
    State.new() |> reply_ok()
  end

  def start_link(_opts) do
    Logger.debug(["starting ", inspect(Mod)])
    GenServer.start_link(__MODULE__, [], name: Mod)
  end

  @impl true
  def handle_call({:register, opts}, {pid, _ref}, %State{} = s) when is_list(opts) do
    opts = Keyword.put_new(opts, :pid, pid)
    State.register(opts, s) |> reply()
  end

  @impl true
  def handle_call({:registrations, opts}, _from, %State{} = s) do
    State.registrations(opts, s) |> reply(s)
  end

  @impl true
  def handle_call({:unregister, ref}, _from, %State{} = s) do
    State.unregister(ref, %State{} = s) |> reply(:ok)
  end

  @impl true
  def handle_cast({:just_saw, opts}, %State{} = s) do
    Keyword.put_new(opts, :missing?, false)
    |> State.notify(s)
    |> noreply()
  end

  @impl true
  def handle_info({:missing, %NotifyTo{} = nt}, %State{} = s) do
    Logger.debug("MISSING\n#{inspect(nt, pretty: true)}")

    Betty.app_error(__MODULE__, name: nt.name, missing: true)

    [name: nt.name, missing?: true]
    |> State.notify(s)
    |> noreply()

    # nt |> NotifyTo.schedule_missing() |> State.save_notify_to(s) |> noreply()
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, %State{} = s) do
    Logger.debug("#{inspect(pid)} exited, removing notify registration(s)")

    State.unregister(ref, s)
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
