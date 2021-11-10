defmodule Alfred.Notify.Entry do
  alias __MODULE__
  alias Alfred.Notify.Memo

  defstruct name: "none",
            pid: nil,
            ref: nil,
            monitor_ref: nil,
            last_notify: DateTime.from_unix!(0),
            ttl_ms: 0,
            interval_ms: 60_000,
            missing_ms: 60_100,
            missing_timer: nil

  @type t :: %Entry{
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
    %Entry{
      name: opts[:name],
      pid: opts[:pid],
      ref: make_ref(),
      monitor_ref: opts[:monitor_ref],
      ttl_ms: opts[:ttl_ms] || 0,
      interval_ms: make_notify_interval(opts),
      missing_ms: make_missing_interval(opts)
    }
  end

  def notify(%Entry{} = e, opts) do
    utc_now = DateTime.utc_now()
    next_notify = DateTime.add(e.last_notify, e.interval_ms, :millisecond)

    # capture ttl_ms from opts (if provided) to handle when a name is
    # registered before being seen
    ttl_ms = opts[:ttl_ms] || e.ttl_ms
    missing_ms = e.missing_ms

    e = %Entry{
      e
      | ttl_ms: ttl_ms,
        missing_ms: make_missing_interval(missing_ms: missing_ms, ttl_ms: ttl_ms)
    }

    case DateTime.compare(utc_now, next_notify) do
      x when x in [:eq, :gt] ->
        Process.send(e.pid, {Alfred, Memo.new(e, opts)}, [])

        %Entry{e | last_notify: DateTime.utc_now()} |> schedule_missing()

      _ ->
        e
    end
  end

  def schedule_missing(%Entry{} = e) do
    unschedule_missing(e)

    %Entry{e | missing_timer: Process.send_after(self(), {:missing, e}, e.missing_ms)}
  end

  def unschedule_missing(%Entry{} = e) do
    if is_reference(e.missing_timer), do: Process.cancel_timer(e.missing_timer)

    %Entry{e | missing_timer: nil}
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
