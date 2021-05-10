defmodule EasyTime do
  @default_tz "America/New_York"

  use Timex
  alias Timex.Duration

  def add_list(d_list) when is_list(d_list) do
    for d <- d_list, reduce: Duration.zero() do
      acc -> Duration.add(acc, to_duration(d))
    end
  end

  def elapsed_ms(dt) do
    case Timex.diff(utc_now(), dt) do
      {:error, _} -> 0
      d -> Duration.to_milliseconds(d, truncate: true)
    end
  end

  def elapsed(start, finish) do
    # must pass the latest datetime to Timex.diff as the first
    # argument to get a positive duration
    case Timex.diff(finish, start, :duration) do
      {:error, _error} -> Duration.zero()
      duration -> duration
    end
  end

  def elapsed?(%Duration{} = max, check) when is_list(check) do
    to_ms(max) <= to_ms(add_list(check))
  end

  def elapsed?(%DateTime{} = reference, %Duration{} = duration) do
    end_dt = Timex.shift(reference, milliseconds: to_ms(duration))
    Timex.after?(utc_now(), end_dt)
  end

  def epoch do
    Timex.epoch() |> Timex.to_datetime()
  end

  def expired?(reference, duration) do
    end_dt = Timex.shift(reference, milliseconds: to_ms(duration))
    Timex.after?(utc_now(), end_dt)
  end

  def from_unix(mtime) do
    DateTime.from_unix!(mtime, :microsecond)
  end

  def is_iso_duration?(arg) when is_binary(arg) do
    case Duration.parse(arg) do
      {:ok, _} -> true
      _error -> false
    end
  end

  def is_iso_duration?(_not_binary), do: false

  # (1 of 2) passed a state, look in opts for :tz
  def local_now(s) when is_map(s), do: get_in(s, [:opts, :tz]) |> local_now()

  # (2 of 2) passed nil default to UTC
  def local_now(:default), do: Timex.now(@default_tz)

  # (3 of 3) passed a binary timezone name
  def local_now(tz) when is_binary(tz), do: Timex.now(tz)

  @doc since: "0.0.27"
  def remaining(finish_dt) do
    elapsed(utc_now(), finish_dt)
  end

  def remaining(start_at, total_duration) do
    Duration.sub(total_duration, elapsed(start_at, utc_now())) |> Duration.abs()
  end

  @doc delegate_to: {Duration, :scale, 2}
  def scale(d, factor) do
    d |> to_duration() |> Duration.scale(factor)
  end

  def shift_future(dt, args) do
    case args do
      d = %Duration{} -> Timex.shift(dt, duration: d)
      iso when is_binary(iso) -> Timex.add(dt, Duration.parse!(iso))
      ms when is_integer(ms) -> Timex.shift(dt, milliseconds: ms)
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
    case args do
      d = %Duration{} -> Timex.shift(dt, duration: Duration.invert(d))
      iso when is_binary(iso) -> Timex.subtract(dt, Duration.parse!(iso))
      ms when is_integer(ms) -> Timex.shift(dt, milliseconds: ms * -1)
      _anything -> dt
    end
  end

  def subtract_list(d_list) when is_list(d_list) do
    for d when is_binary(d) or is_struct(d) <- d_list,
        reduce: Duration.zero() do
      acc -> Duration.sub(acc, to_duration(d)) |> Duration.abs()
    end
  end

  def to_binary(arg) do
    case arg do
      %DateTime{} = x ->
        Timex.to_datetime(x, "America/New_York")
        |> Timex.format!("%a, %b %e, %Y %H:%M:%S", :strftime)

      %Duration{seconds: secs} = x when secs > 900 ->
        Duration.to_minutes(x, truncate: true)
        |> Duration.from_minutes()
        |> Timex.format_duration(:humanized)

      %Duration{} = x ->
        Duration.to_seconds(x, truncate: true)
        |> Duration.from_seconds()
        |> Timex.format_duration(:humanized)

      x ->
        inspect(x, pretty: true)
    end
  end

  def to_duration(d) do
    case d do
      %Duration{} = x -> x
      x when is_binary(x) -> Duration.parse!(x)
      _no_match -> Duration.zero()
    end
  end

  def to_ms(args, default \\ "PT0S") do
    case args do
      nil -> to_duration(default)
      args -> to_duration(args)
    end
    |> Duration.to_milliseconds(truncate: true)
  end

  def to_seconds(args, default \\ "") do
    case args do
      nil -> to_duration(default)
      args -> to_duration(args)
    end
    |> Duration.to_seconds(truncate: true)
  end

  # (2 of 4) accept an Alias struct containing a Device struct
  def ttl_check(m, s, opts) when is_map(m) and is_struct(s) and is_list(opts) do
    #
    # NOTE: the first ttl_ms found in opts is used for the check
    #

    # the case accepts:  (1) %Alias{%Device{}}, (2) legacy %Device{}
    case s do
      %_{ttl_ms: x, device: %_{last_seen_at: y}} -> ttl_check(m, opts ++ [ttl_ms: x, seen_at: y])
      %_{ttl_ms: x, last_seen_at: y} -> ttl_check(m, opts ++ [ttl_ms: x, seen_at: y])
      x -> {:bad_args, "ttl_check unknown struct:\n#{inspect(x, pretty: true)}"}
    end
  end

  # (3 of 4) put into the first arg the ttl_expired? check
  def ttl_check(m, opts) when is_map(m) and is_list(opts) do
    # NOTE: the first ttl_ms found in opts is used
    ttl_ms = opts[:ttl_ms]

    # ttl_ms specified in opts overrides ttl_ms found in struct
    if ttl_expired?(opts[:seen_at], ttl_ms) do
      # put the ttl_ms used for this check into the returned map
      put_in(m, [:ttl_expired], true) |> put_in([:ttl_ms], ttl_ms)
    else
      m
    end
  end

  # (4 of 4) put into the first arg the ttl_expired? check
  def ttl_check(%{ttl_ms: ttl_ms, seen_at: seen_at} = m) do
    (ttl_expired?(seen_at, ttl_ms) && put_in(m, [:ttl_expired], true)) || m
  end

  def ttl_expired?(at, ttl_ms) when is_integer(ttl_ms) do
    ttl_dt = utc_shift_past(ttl_ms)

    Timex.before?(at, ttl_dt)
  end

  @doc since: "0.0.27"
  def valid_ms?(args) do
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

  def unix_now do
    Timex.now() |> DateTime.to_unix(:microsecond)
  end

  def unix_now(unit, opts \\ []) when is_atom(unit) do
    now = Timex.now() |> DateTime.to_unix(unit)

    (opts[:as] == :string && Integer.to_string(now)) || now
  end

  def utc_now do
    Timex.now()
  end

  def utc_shift(args), do: shift_future(utc_now(), args)
  def utc_shift_past(args), do: shift_past(utc_now(), args)

  def zero, do: Duration.zero()
end
