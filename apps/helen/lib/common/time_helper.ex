defmodule Helen.Time.Helper do
  @moduledoc """
  Convenience functions for dealing with Dates, Times and Durations

  """

  use Timex

  @doc """
  Adds a list of durations.  The durations can be either ISO binaries or `%Duration{}`

  Returns a `%Duration{}`
  """
  @doc since: "0.0.27"
  def add_list(d_list) when is_list(d_list) do
    alias Timex.Duration

    for d <- d_list, reduce: Duration.zero() do
      acc -> Duration.add(acc, to_duration(d))
    end
  end

  @doc """
  Check if a DateTime is between `utc_now/0` shifted backwards by the opts list

  ## Examples

      iex> Helen.Time.Helper.between_ref_and_now(ref_datetime, [minutes: 1])
  """
  @doc since: "0.0.27"
  def between_ref_and_now(ref, opts) do
    s = utc_shift_past(opts)
    e = utc_now()

    case Timex.between?(ref, s, e, inclusive: true) do
      res when is_boolean(res) -> true
      # consume errors and default to false
      _res -> false
    end
  end

  @doc """
    Returns a Timex Duration based on the opts or the defaults if the
    the opts are invalid.
  """
  @doc since: "0.0.27"
  def duration_from_list(opts, default) do
    # grab only the opts that are valid for Timex.shift

    case valid_duration_opts?(opts) do
      true -> p_duration(opts)
      false -> p_duration(default)
    end
  end

  @doc """
  Calculates the elapsed duration of start and finish arguments.

  A zero duration is returned if an error occurs while calculating
  the elapsed duration.

  Returns a duration.

  ## Examples

      iex> Helen.Time.Helper.elapsed(start, end)

  """
  @doc since: "0.0.27"
  def elapsed(start, finish) do
    # must pass the latest datetime to Timex.diff as the first
    # argument to get a positive duration
    case Timex.diff(finish, start, :duration) do
      {:error, _error} -> Duration.zero()
      duration -> duration
    end
  end

  @doc """
  Compare the sum of the list (durations or integers representing milliseconds)
  is equal to or exceeds the specified maxiumum.
  """
  @doc since: "0.0.27"
  def elapsed?(%Duration{} = max, check) when is_list(check) do
    to_ms(max) <= to_ms(add_list(check))
  end

  @doc """
  Determines if duration (second argument) has elapsed
  relative to the reference datatime (first argument)

  Returns a boolean.

  ## Examples

      iex> Helen.Time.Helper.elapsed?(reference, duration)

  """
  @doc since: "0.0.27"
  def elapsed?(%DateTime{} = reference, %Duration{} = duration) do
    import Timex, only: [after?: 2, shift: 2]

    end_dt = shift(reference, milliseconds: to_ms(duration))
    after?(utc_now(), end_dt)
  end

  @doc """
    Return epoch as a DateTime
  """
  @doc since: "0.0.26"
  def epoch do
    Timex.epoch() |> Timex.to_datetime()
  end

  @doc """
    Returns a boolean indicating if reference DateTime, shifted by opts
    is after now.

    This is the inverse of current?/3.

    Useful to determining if a DateTime is stale, determining if caching/ttl
    are expired.
  """
  @doc since: "0.0.26"
  def expired?(reference, duration) do
    import Timex, only: [after?: 2, shift: 2]

    end_dt = shift(reference, milliseconds: to_ms(duration))
    after?(utc_now(), end_dt)
  end

  @doc """
  Convert a UNIX mtime (in seconds) to a DateTime with microsecond precision.
  """
  @doc since: "0.0.27"
  def from_unix(mtime) do
    DateTime.from_unix!(mtime, :microsecond)
  end

  @doc """
  Is the argument an ISO duration?
  """
  @doc since: "0.0.27"
  def is_iso_duration?(arg) when is_binary(arg) do
    import Duration, only: [parse: 1]

    case parse(arg) do
      {:ok, _} -> true
      _error -> false
    end
  end

  def is_iso_duration?(_not_binary), do: false

  @doc """
  Convert a list of time options to milliseconds

  Returns an integer.

  ## Examples

      iex> Helen.Time.Helper.list_to_ms([seconds: 1])
      60000

  """
  @doc since: "0.0.27"
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
  Return the current time in the specified timezone

  If is_nil(tz) UTC is used as the timexone
  """
  @doc since: "0.0.27"
  def local_now(tz) do
    if is_nil(tz), do: Timex.now("UTC"), else: Timex.now(tz)
  end

  @doc """
  Calculate the remaining milliseconds given the finish datetime
  """
  @doc since: "0.0.27"
  def remaining(finish_dt) do
    elapsed(utc_now(), finish_dt)
  end

  @doc """
  Calculate the remaining milliseconds given the start datetime and a duration
  representing the total time.
  """
  @doc since: "0.0.27"
  def remaining(start_at, total_duration) do
    alias Timex.Duration

    Duration.sub(total_duration, elapsed(start_at, utc_now())) |> Duration.abs()
  end

  @doc delegate_to: {Timex.Duration, :scale, 2}
  def scale(d, factor) do
    alias Timex.Duration

    d |> to_duration() |> Duration.scale(factor)
  end

  @doc """
  Shifts the given DateTime into the future using the supplied args.

  ## Example Args
     a. %Duration{}
     b. [hours: 1, minutes: 2, seconds: 3]
     c. "PT1H2M3.0S"

  Returns a DateTime.

  """
  @doc since: "0.0.27"
  def shift_future(dt, args) do
    import Timex, only: [shift: 2, add: 2]
    import Timex.Duration, only: [parse!: 1]

    case args do
      l when is_list(l) -> shift(dt, milliseconds: list_to_ms(l, []))
      d = %Duration{} -> shift(dt, duration: d)
      iso when is_binary(iso) -> add(dt, parse!(iso))
      ms when is_integer(ms) -> shift(dt, milliseconds: ms)
      _anything -> dt
    end
  end

  @doc """
  Shifts the given DateTime into the past using the supplied args.  This function
  is the inverse of `shift/2`.

  ## Example Args
     a. %Duration{}
     b. [hours: 1, minutes: 2, seconds: 3]
     c. "PT1H2M3.0S"
     d. 1000 (integer milliseconds)

  Returns a DateTime.

  """
  @doc since: "0.0.27"
  def shift_past(dt, args) do
    import Timex, only: [shift: 2, subtract: 2]
    import Timex.Duration, only: [invert: 1, parse!: 1]

    case args do
      l when is_list(l) -> shift(dt, milliseconds: list_to_ms(l, []) * -1)
      d = %Duration{} -> shift(dt, duration: invert(d))
      iso when is_binary(iso) -> subtract(dt, parse!(iso))
      ms when is_integer(ms) -> shift(dt, milliseconds: ms * -1)
      _anything -> dt
    end
  end

  @doc """
  Subtracts a list of durations and returns the absolute value.

  The durations can be either ISO binaries or `%Duration{}`

  Returns a `%Duration{}`
  """
  @doc since: "0.0.27"
  def subtract_list(d_list) when is_list(d_list) do
    alias Timex.Duration

    for d when is_binary(d) or is_struct(d) <- d_list,
        reduce: Duration.zero() do
      acc -> Duration.sub(acc, to_duration(d)) |> Duration.abs()
    end
  end

  @doc """
  Convert the argument to a binary representation.

  Accepts DateTime and Duration.

  Returns a binary representation or "unsupported".  May raise if
  there is an error related to the DateTime or Duration.

  Defaults to America/New_York timezone.
  """
  @doc since: "0.0.27"
  def to_binary(arg) do
    import Timex, only: [to_datetime: 2, format!: 3, format_duration: 2]
    import Duration, only: [from_minutes: 1, from_seconds: 1]

    case arg do
      %DateTime{} = x ->
        to_datetime(x, "America/New_York")
        |> format!("%a, %b %e, %Y %H:%M:%S", :strftime)

      %Duration{seconds: secs} = x when secs > 900 ->
        Duration.to_minutes(x, truncate: true)
        |> from_minutes()
        |> format_duration(:humanized)

      %Duration{} = x ->
        Duration.to_seconds(x, truncate: true)
        |> from_seconds()
        |> format_duration(:humanized)

      x ->
        inspect(x, pretty: true)
    end
  end

  @doc """
  Convert an ISO binary duration to a `%Duration{}`.

  Also accepts `%Duration{}` and simply returns it unchanged.

  Returns a `%Duration{}` or raises on error.
  """
  @doc since: "0.0.27"
  def to_duration(d) do
    alias Timex.Duration

    case d do
      d when is_list(d) -> list_to_ms(d, []) |> Duration.from_milliseconds()
      %Duration{} = x -> x
      x when is_binary(x) -> Duration.parse!(x)
      _no_match -> Duration.zero()
    end
  end

  @doc """
  Convert the argument to milliseconds.

  Takes an ISO formatted duration binary and an optional default value.
  The default value is used when the first argument is nil.  Useful for
  situations where a configuration does not exist.

  Raises if neither the first argument or the default can not be parse.  The
  default is an empty binary when not supplied.

  Returns an integer representing the milliseconds.

  ## Examples

      iex> Helen.Time.Helper.to_ms("PT1M")
      60000

  """
  @doc since: "0.0.27"
  def to_ms(args, default \\ "PT0S") do
    alias Timex.Duration

    case args do
      nil -> to_duration(default)
      args -> to_duration(args)
    end
    |> Duration.to_milliseconds(truncate: true)
  end

  @doc """
  Convert the argument to seconds.

  Takes an ISO formatted duration binary and an optional default value.
  The default value is used when the first argument is nil.  Useful for
  situations where a configuration does not exist.

  Raises if neither the first argument or the default can not be parse.  The
  default is an empty binary when not supplied.

  Returns an integer representing the seconds.

  ## Examples

      iex> Helen.Time.Helper.to_seconds("PT1M")
      60

  """
  @doc since: "0.0.27"
  def to_seconds(args, default \\ "") do
    alias Timex.Duration

    case args do
      nil -> to_duration(default)
      args -> to_duration(args)
    end
    |> Duration.to_seconds(truncate: true)
  end

  @doc """
  Validates if a ttl has expired

  If passed :ttl_ms in opts the third argument is overriden.

  Returns {:ttl_expired, val} || {:ok, val}

  """
  @doc since: "0.0.27"
  def ttl_check(at, val, ttl_ms, opts) do
    # ttl_ms in opts overrides passed in ttl_ms
    ms = Keyword.get(opts, :ttl_ms, ttl_ms)

    if ttl_expired?(at, ms), do: {:ttl_expired, val}, else: {:ok, val}
  end

  @doc """
  Has a ttl expired?

  Returns a boolean.
  """
  @doc since: "0.0.27"

  def ttl_expired?(at, ttl_ms) when is_integer(ttl_ms) do
    ttl_dt = utc_shift_past(ttl_ms)

    Timex.before?(at, ttl_dt)
  end

  @doc """
  Validates the argument can be converted to an integer representation of
  milliseconds.

  Takes an ISO formatted duration binary.

  Returns a boolean.

  ## Examples

      iex> Helen.Time.Helper.valid_ms?("PT1M")
      true

  """
  @doc since: "0.0.27"
  def valid_ms?(args) do
    alias Timex.Duration

    case args do
      nil ->
        false

      arg when is_binary(arg) ->
        case Duration.parse(args) do
          {:ok, _} -> true
          _failed -> false
        end

      _arg ->
        false
    end
  end

  @doc """
  Checks that a list has at least one valid duration opt

  Returns a boolean.

  ## Examples

      iex> Helen.Time.Helper.valid_duration_opts?([days: 7])
      true

      iex> Helen.Time.Helper.valid_duration_opts?([hello: "doctor"])
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

  @doc """
  Returns the current time as UNIX microseconds

  ## Examples

      iex> Helen.Time.Helper.unix_now()
      ~U[2020-06-22 15:16:02.447077Z]

  """
  @doc since: "0.0.27"
  def unix_now do
    Timex.now() |> DateTime.to_unix(:microsecond)
  end

  @doc """
  Returns the current time as UNIX in specified unit

  ## Examples

      iex> Helen.Time.Helper.unix_now(:milliseconds)
      ~U[2020-06-22 15:16:02.44Z]

  """
  @doc since: "0.0.27"
  def unix_now(unit) when is_atom(unit) do
    Timex.now() |> DateTime.to_unix(unit)
  end

  @doc """
  Returns the current datetime in the UTC timezone

  ## Examples

      iex> Helen.Time.Helper.utc_now()
      ~U[2020-06-22 15:16:02.447077Z]

  """
  @doc since: "0.0.27"
  def utc_now do
    Timex.now()
  end

  @doc """
  Shifts UTC now into the future using the supplied args.

  ## Example Args
     a. %Duration{}
     b. [hours: 1, minutes: 2, seconds: 3]
     c. "PT1H2M3.0S"

  Returns a DateTime.

  """
  @doc since: "0.0.27"
  def utc_shift(args), do: shift_future(utc_now(), args)

  @doc """
  Shifts UTC now into the past using the supplied args.  This function
  is the inverse of `utc_shift/1`.

  ## Example Args
     a. %Duration{}
     b. [hours: 1, minutes: 2, seconds: 3]
     c. "PT1H2M3.0S"
     d. 1000 (integer milliseconds)

  Returns a DateTime.

  """
  @doc since: "0.0.27"
  def utc_shift_past(args), do: shift_past(utc_now(), args)

  @doc """
  Returns a duration of zero.  Simply put, this is a wrapper for `Timex.Duration.zero/0`

  Returns a duration.

  """
  @doc since: "0.0.27"
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

  defp duration_opts(opts) do
    case opts do
      [o] when is_nil(o) ->
        []

      o when is_list(o) ->
        Keyword.take(o, [
          :microseconds,
          :milliseconds,
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
end
