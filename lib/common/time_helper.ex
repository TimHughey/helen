defmodule Helen.Time.Helper do
  @moduledoc """
  Convenience functions for dealing with Dates, Times and Durations

  """

  use Timex

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

  def duration_invert(opts) when is_list(opts) do
    duration_from_list(opts, []) |> Duration.invert()
  end

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

  def utc_shift(opts) when is_list(opts) do
    utc_now() |> Timex.shift(opts)
  end

  def utc_shift(%Duration{} = d), do: utc_now() |> Timex.shift(duration: d)

  def utc_shift(_anything), do: utc_now()

  def utc_shift_past(opts) when is_list(opts),
    do: utc_now() |> Timex.shift(duration: duration_invert(opts))

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
