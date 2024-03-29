defmodule Solar do
  @moduledoc """
  A library that provides information about the sun and in particular; events.

  The algorithms/math used are from:

    https://github.com/mikereedell/sunrisesunsetlib-java

  This module is a rewrite of:
    https://github.com/bengtson/solar

  All calls to `Solar` library are through this module.
  """

  @doc """
  Provides sunrise or sunset times for a provided location and date.

  The function takes a binary describing the specific event (e.g. sunrise, astro rise, civil set) and
  a list of opts to further define the location, date and timezone.

  The function returns either:
    `DateTime`
    '{:error, reason}'
  """
  def event(type, opts \\ [])

  def event("beginning of day", opts) when is_list(opts) do
    case event("sunrise", opts) do
      %DateTime{} = sunrise -> Timex.beginning_of_day(sunrise)
      x -> x
    end
  end

  def event("end of day", opts) when is_list(opts) do
    case event("sunset", opts) do
      %DateTime{} = sunrise -> Timex.end_of_day(sunrise)
      x -> x
    end
  end

  def event("noon", opts) when is_list(opts) do
    with %DateTime{} = sunrise <- event("sunrise", opts),
         %DateTime{} = sunset <- event("sunset", opts) do
      half_day_secs = (Timex.diff(sunset, sunrise, :second) / 2) |> trunc()

      Timex.shift(sunrise, seconds: half_day_secs)
    else
      x -> x
    end
  end

  def event(type, opts) when is_binary(type) and is_list(opts) do
    Solar.Opts.new(type, opts) |> Solar.Events.event()
  end

  def event_opts(:binaries) do
    base = ["beginning of day", "end of day", "noon", "sunrise", "sunset"]
    types = ["astro", "civil", "nautical", "sun"]

    for type <- types, zenith <- ["rise", "set"], reduce: base do
      acc -> ["#{type} #{zenith}" | acc]
    end
    |> Enum.sort()
  end
end
