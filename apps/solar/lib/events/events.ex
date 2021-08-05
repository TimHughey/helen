defmodule Solar.Opts do
  alias __MODULE__

  defstruct type: :rise,
            zenith: :official,
            latitude: 40.21089564609479,
            longitude: -74.0109850020794,
            timezone: "America/New_York",
            valid?: false,
            invalid_reason: ""

  @type event_type() :: :rise | :set
  @type zenith() :: :astro | :nautical | :civil | :official
  @type date_option() :: DateTime.t()
  @type t :: %Opts{
          type: event_type(),
          zenith: zenith(),
          latitude: float(),
          longitude: float(),
          timezone: Calendar.time_zone(),
          valid?: boolean(),
          invalid_reason: String.t()
        }

  def new(opts) do
    default = %Opts{}

    %Opts{
      type: opts[:type] || default.type,
      zenith: opts[:zenith] || default.zenith,
      latitude: opts[:latitude] || default.latitude,
      longitude: opts[:longitude] || default.longitude,
      timezone: opts[:timezone] || default.timezone
    }
  end
end

defmodule Solar.Events do
  require Logger

  alias __MODULE__
  alias Solar.Opts

  defstruct type: nil,
            lat_deg: nil,
            lat_rad: nil,
            long_deg: nil,
            long_rad: nil,
            zenith: nil,
            loc_date: nil,
            timezone: nil,
            base_long_hour: nil,
            long_hour: nil,
            mean_anomaly: nil,
            sun_true_longitude: nil,
            cos_sun_local_hour: nil,
            sun_local_hour: nil,
            right_ascension: nil,
            local_mean_time: nil,
            valid?: true,
            invalid_reason: ""

  @moduledoc """
  The `Solar.Events` module provides the calculations for sunrise and sunset
  times. This is likely to be refactored as other events are added.
  """

  @doc """
  The event function takes a minimum of two parameters, the event of interest
  which can be either :rise or :set and the latitude and longitude. Additionally
  a list of options can be provided as follows:

    * `date:` allows a value of either `:today` or an Elixir date. The default
      if this option is not provided is the current day.
    * `zenith:` can be set to define the sunrise or sunset. See the `Zeniths`
      module for a set of standard zeniths that are used. The default if a
      zenith is not provided is `:official` most commonly used for sunrise and
      sunset.
    * `timezone:` can be provided and should be a standard timezone identifier
      such as "America/Chicago". If the option is not provided, the timezone is
      taken from the system and used.

  ## Examples

  The following, with out any options and run on December 25:

      iex> Solar.event (:rise, {39.1371, -88.65})
      {:ok,~T[07:12:26]}

      iex> Solar.event (:set, {39.1371, -88.65})
      {:ok,~T[16:38:01]}

  The coordinates are for Lake Sara, IL where sunrise on this day will be at 7:12:26AM and sunset will be at 4:38:01PM.
  """

  @type latitude :: number
  @type longitude :: number
  @type message :: String.t()

  @spec event(Opts.t()) :: {:ok, Time.t()} | {:error, message}
  def event(%Opts{} = opts) do
    calc = %Events{
      type: opts.type,
      zenith: opts.zenith |> Zeniths.lookup(),
      lat_deg: opts.latitude,
      lat_rad: opts.latitude |> deg_to_rad(),
      long_deg: opts.longitude,
      long_rad: opts.longitude |> deg_to_rad(),
      loc_date: Timex.local(opts.timezone) |> Timex.to_date(),
      timezone: opts.timezone
    }

    with {:type, true} <- {:type, opts.type in [:rise, :set]},
         # Computes the base longitude hour, lngHour in the algorithm. The longitude
         # of the location of the solar event divided by 15 (deg/hour).
         %Events{} = x <- %Events{calc | base_long_hour: calc.long_deg / 15.0},
         %Events{} = x <- longitude_hour(x),
         # Computes the mean anomaly of the Sun, M in the algorithm.
         %Events{} = x <- %Events{x | mean_anomaly: x.long_hour * 0.9856 - 3.289},
         %Events{} = x <- sun_true_longitude(x),
         %Events{valid?: true} = x <- cos_sun_local_hour(x),
         %Events{} = x <- sun_local_hour(x),
         %Events{} = x <- right_ascension(x),
         %Events{} = x <- local_mean_time(x) do
      # calculate the final result as a DateTime for the location date with the requested sun position
      tzi = Timex.timezone(x.timezone, x.loc_date)
      offset_minutes = Timex.Timezone.total_offset(tzi)

      utc_time = x.local_mean_time - x.base_long_hour
      local_time = utc_time + offset_minutes / 3600.0

      time = local_time
      hr = time |> trunc()
      tmins = (time - hr) * 60
      min = tmins |> trunc()
      tsecs = (tmins - min) * 60
      sec = tsecs |> trunc()

      Timex.now(x.timezone) |> Timex.set(hour: hr, minute: min, second: sec, microsecond: 0)
    else
      {:type, false} -> {:error, "type must be either :rise or :set"}
      %Events{invalid_reason: x} -> {:error, x}
    end
  end

  # Computes the longitude time.
  # Uses: loc_date and type
  # Sets: longitude_hour
  defp longitude_hour(%Events{type: type} = calc) do
    offset = if(type == :rise, do: 6.0, else: 18.0)

    dividend = offset - calc.long_deg / 15.0
    addend = dividend / 24.0

    %Events{calc | long_hour: Timex.day(calc.loc_date) + addend}
  end

  # Computes the true longitude of the sun, L in the algorithm, at the
  # given location, adjusted to fit in the range [0-360].
  defp sun_true_longitude(%Events{mean_anomaly: mean_anomaly} = calc) do
    sin_mean_anomaly = mean_anomaly |> deg_to_rad() |> :math.sin()
    sin_double_mean_anomoly = (mean_anomaly * 2.0) |> deg_to_rad() |> :math.sin()
    first_part = mean_anomaly + sin_mean_anomaly * 1.916
    second_part = sin_double_mean_anomoly * 0.020 + 282.634
    true_longitude = first_part + second_part

    sun_true_longitude = if(true_longitude > 360.0, do: true_longitude - 360.0, else: true_longitude)

    %Events{calc | sun_true_longitude: sun_true_longitude}
  end

  defp cos_sun_local_hour(%Events{lat_rad: lat_rad, sun_true_longitude: sun_true_long, zenith: zenith} = calc) do
    sin_sun_declination = (sun_true_long |> deg_to_rad() |> :math.sin()) * 0.39782
    cos_sun_declination = sin_sun_declination |> :math.asin() |> :math.cos()
    cos_zenith = zenith |> deg_to_rad() |> :math.cos()
    sin_latitude = lat_rad |> :math.sin()
    cos_latitude = lat_rad |> :math.cos()

    cos_sun_local_hour =
      (cos_zenith - sin_sun_declination * sin_latitude) /
        (cos_sun_declination * cos_latitude)

    cond do
      cos_sun_local_hour < -1.0 -> %Events{calc | valid?: false, invalid_reason: "cos_sun_local_hour < -1.0"}
      cos_sun_local_hour > +1.0 -> %Events{calc | valid?: false, invalid_reason: "cos_sun_local_hour > +1.0"}
      true -> %Events{calc | cos_sun_local_hour: cos_sun_local_hour}
    end
  end

  defp sun_local_hour(%Events{type: type, cos_sun_local_hour: cos_sun_local_hour} = calc) do
    local_hour = cos_sun_local_hour |> :math.acos() |> rad_to_deg()

    %Events{calc | sun_local_hour: if(type == :rise, do: (360.0 - local_hour) / 15, else: local_hour / 15)}
  end

  # Computes the suns right ascension, RA in the algorithm, adjusting for
  # the quadrant of L and turning it into degree-hours. Will be in the
  # range [0,360].
  defp right_ascension(%Events{sun_true_longitude: sun_true_long} = calc) do
    tanl = sun_true_long |> deg_to_rad() |> :math.tan()
    inner = rad_to_deg(tanl) * 0.91764
    right_ascension = inner |> deg_to_rad() |> :math.atan() |> rad_to_deg()

    right_ascension =
      cond do
        right_ascension < 0.0 -> right_ascension + 360.0
        right_ascension > 360.0 -> right_ascension - 360.0
        true -> right_ascension
      end

    long_quad = ((sun_true_long / 90.0) |> trunc()) * 90.0
    right_quad = ((right_ascension / 90.0) |> trunc()) * 90.0
    val = (right_ascension + (long_quad - right_quad)) / 15.0

    %Events{calc | right_ascension: val}
  end

  defp local_mean_time(%Events{} = calc) do
    local_mean_time = calc.sun_local_hour + calc.right_ascension - calc.long_hour * 0.06571 - 6.622

    val =
      cond do
        local_mean_time < 0 -> local_mean_time + 24.0
        local_mean_time > 24 -> local_mean_time - 24.0
        true -> local_mean_time
      end

    %Events{calc | local_mean_time: val}
  end

  # Converts degrees to radians.
  defp deg_to_rad(degrees) do
    degrees / 180.0 * :math.pi()
  end

  defp rad_to_deg(radians) do
    radians * 180.0 / :math.pi()
  end

  @doc """
  Calculates the hours of daylight returning as a time with hours, minutes and seconds.
  """
  def daylight(rise, set) do
    hours_to_time(time_to_hours(set) - time_to_hours(rise))
  end

  defp time_to_hours(time) do
    time.hour + time.minute / 60.0 + time.second / (60.0 * 60.0)
  end

  defp hours_to_time(hours) do
    h = Kernel.trunc(hours)
    value = (hours - h) * 60
    m = Kernel.trunc(value)
    value = (value - m) * 60
    s = Kernel.trunc(value)
    {:ok, time} = Time.new(h, m, s)
    time
  end
end
