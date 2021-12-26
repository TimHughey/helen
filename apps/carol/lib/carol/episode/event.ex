defmodule Carol.Episode.Event do
  @asn1_time_parts [:hour, :minute, :second, :microsecond]
  @simple_time_parts [:hour, :minute, :second]
  @solar_events Solar.event_opts(:binaries)

  @doc since: "0.3.0"
  def fixed(parts, opts) when is_list(opts) do
    ref_dt = opts[:ref_dt]

    parts
    |> Map.take(@simple_time_parts)
    |> then(fn time_parts -> struct(ref_dt, time_parts) end)
  end

  @doc since: "0.3.0"
  def parse(opts) when is_list(opts) do
    {event, opts_rest} = Keyword.pop(opts, :event, "beginning of day")
    {shift_opts, opts_rest} = Keyword.pop(opts_rest, :shift_opts, [])

    shift_opts = Keyword.take(shift_opts, shift_options())

    case parse(event) do
      %{sunref: x} when is_binary(x) -> solar_event(x, opts_rest)
      %{asn1: x} when is_binary(x) -> from_asn1(x, opts_rest)
      %{hour: _} = parts -> fixed(parts, opts_rest)
    end
    |> Timex.shift(shift_opts)
  end

  def parse(event) when is_atom(event) do
    event |> to_string() |> String.replace("_", " ") |> parse()
  end

  def parse(event) when event in @solar_events, do: %{sunref: event}

  def parse(event) when is_binary(event) do
    parts = regex(event)

    for {k, v} <- parts, into: %{} do
      case {String.to_atom(k), v} do
        {:asn1, _} = kv -> kv
        {key, val} when key in @simple_time_parts -> {key, String.to_integer(val)}
      end
    end
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp from_asn1(asn1, opts) when is_binary(asn1) do
    ref_dt = opts[:ref_dt]
    timezone = opts[:timezone]

    asn1
    |> Timex.parse!("{ASN1:GeneralizedTime:Z}")
    |> Timex.to_datetime(timezone)
    |> Map.take(@asn1_time_parts)
    |> then(fn fields -> struct(ref_dt, fields) end)
  end

  def shift_options,
    do: [
      :microseconds,
      :milliseconds,
      :seconds,
      :minutes,
      :hours,
      :days,
      :weeks,
      :months,
      :years,
      :duration
    ]

  @solar_opts [:timezone, :ref_dt, :latitude, :longitude]
  defp solar_event(event, opts) do
    event_opts = Keyword.take(opts, @solar_opts)

    Solar.event(event, event_opts)
  end

  defp regex(event) do
    ~r"""
    ^fixed\s(?<hour>\d\d):(?<minute>\d\d):(?<second>\d\d)$
    |
    ^(?<asn1>\d{14}.\d{1,}Z)$
    """x
    |> Regex.named_captures(event)
    |> Enum.reject(fn {_k, v} -> v == "" end)
  end
end
