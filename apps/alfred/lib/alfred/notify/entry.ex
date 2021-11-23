defmodule Alfred.Notify.Entry do
  alias __MODULE__
  alias Alfred.Notify.Memo

  defstruct name: "none",
            pid: nil,
            ref: nil,
            monitor_ref: nil,
            last_notify_at: DateTime.from_unix!(0),
            ttl_ms: 0,
            interval_ms: 60_000,
            missing_ms: 60_000,
            missing_timer: nil

  @type t :: %Entry{
          name: String.t(),
          pid: pid(),
          ref: reference(),
          monitor_ref: reference(),
          last_notify_at: DateTime.t(),
          ttl_ms: non_neg_integer(),
          interval_ms: pos_integer(),
          missing_ms: pos_integer(),
          missing_timer: reference()
        }

  @type frequency_opts :: :all | [interval_ms: pos_integer()]
  @type ttl_ms :: non_neg_integer()
  @type new_opts() :: [
          name: binary(),
          pid: pid(),
          link: boolean(),
          ttl_ms: ttl_ms(),
          missing_ms: pos_integer(),
          frequency: frequency_opts()
        ]
  @spec new(new_opts()) :: Entry.t()
  def new(args) when is_list(args) do
    pid = args[:pid]

    # NOTE: only link if requested but always monitor
    if args[:link] && pid != self(), do: Process.link(pid)

    %Entry{
      name: args[:name],
      pid: args[:pid],
      ref: make_ref(),
      monitor_ref: Process.monitor(pid),
      interval_ms: make_notify_interval(args)
    }
    |> update_ttl_ms(args)
    |> update_missing_ms(args)
    |> schedule_missing()
  end

  @type notify_opts :: [missing?: boolean(), seen_at: DateTime.t()]
  @spec notify(Entry.t(), opts :: notify_opts()) :: Entry.t()
  def notify(%Entry{} = e, opts) do
    seen_at = opts[:seen_at] || DateTime.utc_now()
    next_notify_at = Timex.shift(e.last_notify_at, milliseconds: e.interval_ms)

    # notifications only occur when a name is known so update the ttl_ms
    # then update the missing interval considering the ttl_ms
    e = update_ttl_ms(e, opts) |> update_missing_ms()

    if Timex.compare(seen_at, next_notify_at) >= 0 do
      memo = Memo.new(e, opts)
      Process.send(e.pid, {Alfred, memo}, [])

      %Entry{e | last_notify_at: seen_at} |> schedule_missing()
    else
      e
    end
  end

  def schedule_missing(%Entry{} = e) do
    unschedule_missing(e)

    missing_timer = Process.send_after(self(), {:missing, e}, e.missing_ms)

    %Entry{e | missing_timer: missing_timer}
  end

  def unschedule_missing(%Entry{} = e) do
    if is_reference(e.missing_timer), do: Process.cancel_timer(e.missing_timer)

    %Entry{e | missing_timer: nil}
  end

  defp make_missing_interval(opts) when is_list(opts) do
    # NOTE:
    # -missing_ms controls the missing timer frequenxy
    #
    # most notify registrations are done at startup before ttl_ms is available
    #
    # 1. use missing_ms when ttl_ms is unknown
    # 2. use ttl_ms when available (e.g. after a name becomes known)

    missing_ms = opts[:missing_ms] || 60_000
    ttl_ms = opts[:ttl_ms] || 0

    cond do
      ttl_ms == 0 and is_integer(missing_ms) -> missing_ms
      is_integer(ttl_ms) > 0 -> ttl_ms
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

  defp update_missing_ms(%Entry{} = e, opts \\ []) do
    missing_ms = opts[:missing_ms] || e.missing_ms
    ttl_ms = opts[:ttl_ms] || e.ttl_ms

    missing_opts = [missing_ms: missing_ms, ttl_ms: ttl_ms]
    %Entry{e | missing_ms: make_missing_interval(missing_opts)}
  end

  defp update_ttl_ms(%Entry{} = e, opts) do
    %Entry{e | ttl_ms: opts[:ttl_ms] || e.ttl_ms}
  end
end
