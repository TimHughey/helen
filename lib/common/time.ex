defmodule TimeSupport do
  @moduledoc false
  use Timex

  def elapsed(%Duration{} = d) do
    alias Timex.Duration, as: D

    D.elapsed(D.now(), d) |> D.abs()
  end

  @doc """
    Returns a boolean indicating if reference DateTime, shifted by opts
    is before now.

    This is the inverse of expired?/3.

    Useful to determining if a DateTime is stale, deteriming if caching/ttl
    are expired.
  """
  @doc since: "0.0.26"
  def current?(ref, key \\ :interval, opts \\ [interval: [minutes: 1]]) do
    shift_opts = Keyword.get(opts, key, minutes: 1)

    ref_shifted = Timex.shift(ref, shift_opts)

    Timex.before?(ref_shifted, utc_now())
  end

  @doc """
    Returns a boolean indicating if reference DateTime, shifted by opts
    is after now.

    This is the inverse of current?/3.

    Useful to determining if a DateTime is stale, deteriming if caching/ttl
    are expired.
  """
  @doc since: "0.0.26"
  def expired?(ref, key \\ :interval, opts \\ [interval: [minutes: 1]]) do
    shift_opts = Keyword.get(opts, key, minutes: 1)

    ref_shifted = Timex.shift(ref, shift_opts)

    Timex.after?(utc_now(), ref_shifted)
  end

  @doc """
    Returns a Timex Duration based on the opts or the defaults if the
    the opts are invalid.
  """

  def duration_from_list(opts, default) do
    # grab only the opts that are valid for Timex.shift

    case valid_duration_opts?(opts) do
      true -> p_duration(opts)
      false -> p_duration(default)
    end
  end

  @doc deprecated: "Use duration_from_list/1 instead"
  def duration(opts), do: duration_from_list(opts, [])

  def duration_invert(opts) when is_list(opts) do
    duration_from_list(opts, []) |> Duration.invert()
  end

  defdelegate ms_from_list(opts), to: TimeSupport, as: :duration_ms

  def duration_ms(opts) when is_struct(opts) or is_list(opts) do
    case opts do
      opts when is_list(opts) -> duration_from_list(opts, [])
      opts -> opts
    end
    |> Duration.to_milliseconds(truncate: true)
  end

  def duration_opts(opts) do
    case opts do
      [o] when is_nil(o) ->
        []

      o when is_list(o) ->
        Keyword.take(o, [
          :microseconds,
          :seconds,
          :minutes,
          :hours,
          :days,
          :weeks,
          :months,
          :years
        ])

      _o ->
        []
    end
  end

  def duration_secs(opts) when is_struct(opts) or is_list(opts) do
    case opts do
      opts when is_list(opts) -> duration_from_list(opts, [])
      opts -> opts
    end
    |> Duration.to_seconds(truncate: true)
  end

  @doc """
    Return epoch as a DateTime
  """
  @doc since: "0.0.26"
  def epoch do
    Timex.epoch() |> Timex.to_datetime()
  end

  def from_unix(mtime) do
    {:ok, dt} = DateTime.from_unix(mtime)
    Timex.shift(dt, microseconds: 1) |> Timex.shift(microseconds: -1)
  end

  def humanize_duration(%Duration{} = d) do
    alias Timex.Format.Duration.Formatter

    Formatter.format(d, :humanized)
  end

  def humanize_duration(_anything) do
    alias Timex.Format.Duration.Formatter

    Formatter.format(Duration.zero(), :humanized)
  end

  @doc """
  Has the interval defined by the key from the opts elapsed relative to the
  reference Duration?
  """
  @doc since: "0.0.26"
  def interval_elapsed?(ref, opts, key) do
    interval = interval_from_opts(opts, key)

    Timex.after?(elapsed(ref), interval)
  end

  @doc """
  Returns a Timex Duration from the opts list using the key passed
  """
  @doc since: "0.0.26"
  def interval_from_opts(opts, key) when is_list(opts) and is_atom(key) do
    interval_opts = Keyword.get(opts, key, minutes: 1)
    duration_from_list(interval_opts, [])
  end

  defdelegate now, to: Timex.Duration

  def list_to_ms(opts, defaults) do
    # after hours of searching and not finding an existing capabiility
    # in Timex we'll roll our own consisting of multiple Timex functions.

    actual_opts =
      cond do
        valid_duration_opts?(opts) -> opts
        valid_duration_opts?(defaults) -> defaults
        true -> [weeks: 12]
      end

    ~U[0000-01-01 00:00:00Z]
    |> Timex.shift(duration_opts(actual_opts))
    |> Timex.to_gregorian_microseconds()
    |> Duration.from_microseconds()
    |> Duration.to_milliseconds(truncate: true)
  end

  @doc """
    Converts a Timex standard opts list (e.g. [minutes: 1, seconds: 2])
    to a Timex Duration then to truncated milliseconds
  """
  @doc since: "0.0.26"
  def opts_as_ms(opts), do: duration_ms(opts)

  @doc """
    Returns the remaining milliseconds using a reference Duration and
    the time elapsed between now and the reference
  """
  @doc since: "0.0.26"
  def remaining_ms(ref, max) do
    alias Timex.Duration, as: D

    D.diff(elapsed(ref), duration_from_list(max, []))
    |> D.abs()
    |> D.to_milliseconds(truncate: true)
  end

  def ttl_check(at, val, ttl_ms, opts) do
    # ttl_ms in opts overrides passed in ttl_ms
    ms = Keyword.get(opts, :ttl_ms, ttl_ms)

    if ttl_expired?(at, ms), do: {:ttl_expired, val}, else: {:ok, val}
  end

  def ttl_expired?(at, ttl_ms) when is_integer(ttl_ms) do
    shift_ms = ttl_ms * -1
    ttl_dt = Timex.now() |> Timex.shift(milliseconds: shift_ms)

    Timex.before?(at, ttl_dt)
  end

  def unix_now do
    Timex.now() |> DateTime.to_unix(:microsecond)
  end

  def unix_now(unit) when is_atom(unit) do
    Timex.now() |> DateTime.to_unix(unit)
  end

  def utc_now do
    Timex.now()
  end

  def utc_shift(opts) when is_list(opts) do
    utc_now() |> Timex.shift(opts)
  end

  def utc_shift(%Duration{} = d), do: utc_now() |> Timex.shift(duration: d)

  def utc_shift(_anything), do: utc_now()

  def utc_shift_past(opts) when is_list(opts),
    do: utc_now() |> Timex.shift(duration: duration_invert(opts))

  @doc """
  Checks that a list has at least one valid duration opt

  Returns a boolean.

  ## Examples

      iex> TimeSupport.valid_duration_opts?([days: 7])
      true

      iex> TimeSupport.valid_duration_opts?([hello: "doctor"])
      false
  """
  @doc since: "0.0.27"
  def valid_duration_opts?(opts) do
    # attempt to handle whatever is passed us by wrapping in a list and flattening
    opts = [opts] |> List.flatten()

    case duration_opts(opts) do
      [x] when is_nil(x) -> false
      x when x == [] -> false
      _x -> true
    end
  end

  def zero, do: Duration.zero()

  ##
  ## PRIVATE
  ##

  defp p_duration(opts) do
    # after hours of searching and not finding an existing capabiility
    # in Timex we'll roll our own consisting of multiple Timex functions.

    ~U[0000-01-01 00:00:00Z]
    |> Timex.shift(duration_opts(opts))
    |> Timex.to_gregorian_microseconds()
    |> Duration.from_microseconds()
  end
end
