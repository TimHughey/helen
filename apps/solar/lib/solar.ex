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

  def event("noon", opts) when is_list(opts) do
    with %DateTime{} = sunrise <- event("sunrise", opts),
         %DateTime{} = sunset <- event("sunset", opts) do
      half_day_secs = (DateTime.diff(sunset, sunrise, :second) / 2) |> trunc()

      DateTime.add(sunrise, half_day_secs, :second)
    else
      x -> x
    end
  end

  def event(type, opts) when is_binary(type) and is_list(opts) do
    Solar.Opts.new(type, opts) |> Solar.Events.event()
  end
end
