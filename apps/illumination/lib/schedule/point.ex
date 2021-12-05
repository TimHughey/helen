defmodule Illumination.Schedule.Point do
  alias __MODULE__
  alias Alfred.ExecCmd

  defstruct sunref: nil, offset_ms: 0, at: nil, cmd: %ExecCmd{cmd: "off"}

  @type t :: %Point{
          sunref: String.t(),
          offset_ms: integer(),
          at: DateTime.t(),
          cmd: ExecCmd.t()
        }

  def calc_at(%Point{} = pt, opts \\ []) when is_list(opts) do
    case parse_sunref(pt.sunref) do
      %{sunref: _} -> solar_event(pt, opts)
      time_parts -> fixed_event(pt, Enum.into(time_parts, []) ++ opts)
    end
    |> offset()
  end

  @time_parts [:hour, :minute, :second]
  def fixed_event(%Point{} = pt, opts) do
    {ref_dt, opts_rest} = Keyword.pop(opts, :datetime)
    {time_parts, _} = Keyword.split(opts_rest, @time_parts)

    %Point{pt | at: struct(ref_dt, time_parts)}
  end

  @regex ~r"""
  ^fixed\s(?<hour>\d{2}):(?<minute>\d{2}):(?<second>\d{2})$
  |
  ^(?<sunref>[a-z\s]+)$
  """x
  def parse_sunref(sunref) do
    Regex.named_captures(@regex, sunref)
    |> Enum.reject(fn {_, v} -> v == "" end)
    |> rationalize_parts()
  end

  def rationalize_parts(parts) do
    for {k, v} <- parts, into: %{} do
      case {String.to_atom(k), v} do
        {:sunref, _sunref} = kv -> kv
        {key, val} when key in @time_parts -> {key, String.to_integer(val)}
      end
    end
  end

  def solar_event(%Point{} = pt, opts) do
    event_opts = Keyword.take(opts, [:timezone, :datetime])

    %Point{pt | at: Solar.event(pt.sunref, event_opts)}
  end

  defp offset(%Point{at: at} = pt) do
    %Point{pt | at: Timex.shift(at, milliseconds: pt.offset_ms)}
  end
end
