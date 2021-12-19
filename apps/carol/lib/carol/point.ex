defmodule Carol.Point do
  @moduledoc """
  A `Point` describes the date and time to execute a command.

  ## Introduction

  The design of `Point` provides an abstraction of the `DateTime`
  the command is executed focusing on the _time_ vs. the date. With
  that in mind, the key aspect of a `Point` is the ability to define either
  a variable or fixed time.

  When used during runtime, a `Point` computes the specific `DateTime` to execute the command
  by combining the time (variable or fixed) with a date provided via options

  ## Variable Time

  A `Solar` event can be specified as the time of day to execute the command.
  Using a `Solar` event allows the time of day to continously change based on
  the date and timezone passed as options to the functions in this module.

  This is useful when one wants a command executed at sunset, specific to a
  location, each day.

  See `Solar` for the events available.

  ## Fixed Time

  A fixed time of day (e.g. 08:00) can be specified in two different flavors.

  ### `HH:MM:SS`

  `HH:MM:SS` simply describes the hour, minute and second of a day.

  ### `ASN1:GeneralizedTime:Z`

  `ASN1:GeneralizedTime:Z` is a bit more nuanced since it includes a time __and__ date
  component.  The time component is used in calculations and the date component
  is simply ignored.

  This format is supported for convenience when building a `Point` during runtime
  (e.g. outside a static configuration file) and enables finer time resolution (e.g. milliseconds) than `HH:MM:SS`.

  `Timex` provides functionality for formatting a `DateTime` as a generalized date/time.
  ```
  Timex.now() |> Timex.format({ASN1:GeneralizedTime:Z})
  #=> {:ok, "20211211215911.129273Z"}
  ```

  ## Shared Options
  All functions in this module that calculate the datetime of a `Point` require
  the following options:

  * `:datetime` - specifies the __date_ component
  * `:timezone` - timezone of the final `DateTime` and passed to `Solar.event/2`.

  """
  alias __MODULE__
  alias Alfred.ExecCmd

  defstruct type: :none, sunref: :none, offset_ms: 0, at: :none, cmd: :default

  @type t :: %Point{
          type: atom(),
          sunref: String.t(),
          offset_ms: integer(),
          at: DateTime.t(),
          cmd: ExecCmd.t()
        }

  @asn1_format "{ASN1:GeneralizedTime:Z}"
  @time_parts [:hour, :minute, :second]
  @time_parts_ext [:hour, :minute, :second, :microsecond]

  @doc """
  Calculate the embedded `DateTime` of a `Point`

  ## Required Options

  * `:datetime` - `DateTime` to use for the date
  * `:timezone` - timezone of the final embedded `DateTime`

  ## What's a Sunref?

  The `sunref` describes a specific time of day merged into
  `:datetime` to create the final `DateTime` of the `Point`.

  Said differently, a `Point` can describe any date/time using the
  combination of `sunref` and `:datetime`. The `sunref` provides the
   __time of day__ and `:datetime` provides the __date__.

  ## Permitted Sunref values

  1. `01:15:30` - hour, minute and second in 24H format
  2. `civil rise` - event supported by `Solar.event/2`
  3. `20211211215911.129273Z` - ANS1 numerical datetime



  ## Examples
  ```
  # Point with sunref to use for calculation of DateTime
  point = %Point(sunref: "civil twilight rise")

  # required options and a Solar event
  opts = [datetime: Timex.now("America/New_York"), timezone: "America/New_York"]
  Point(sunref: "civil twilight rise")
  #=> %Point{at: %DateTime{}}

  # required options and
  opts = [datetime: Timex.now("America/New_York"), timezone: "America/New_York"]
  Point(sunref: "20211211215911.129273Z")
  #=> %Point{at: %DateTime{}}

  ```
  """
  @doc since: "0.1.0"
  def calc_at(%Point{} = pt, opts \\ []) when is_list(opts) do
    case parse_sunref(pt.sunref) do
      %{sunref: x} when is_binary(x) -> solar_event(pt, opts)
      %{asn1: x} -> from_asn1(pt, x, opts)
      %{hour: _} = parts -> fixed_event(pt, Enum.into(parts, []) ++ opts)
    end
    |> offset()
  end

  @doc since: "0.2.1"
  def clear_at(%Point{} = point), do: struct(point, at: :none)

  @doc """
  Return the embedded `ExecCmd` with name set to `equipment`

  > The embedded `ExecCmd` intentionally has an invalid name which muxt
  > be set prior to calling `Alfred.execute/1`.
  >
  > This design decision encourages using the most recent equipment
  > name from a configuration or other source (e.g. state).

  > Call this function to retrieve a valid `ExecCmd` which can be
  > passed to `Alfred.execute/1`.

  ## Example
  ```
  # equipment as a binary
  Point.cmd(%Point{}, "equipment name")
  #=> %ExecCmd{name: "equipment name"}

  # equipment as a zero arity function
  Point.cmd(%Point{}, fn -> "from function" end)
  #=> %ExecCmd{name: "from function"}

  ```
  """
  @doc since: "0.2.1"
  def cmd(%Point{} = point, equipment_fn) when is_function(equipment_fn) do
    cmd(point, equipment_fn.())
  end

  def cmd(%Point{} = pt, equipment) when is_binary(equipment) do
    case {pt.type, pt.cmd} do
      {:start, :default} -> ExecCmd.new(cmd: "on")
      {:finish, :default} -> ExecCmd.new(cmd: "off")
      {_type, %ExecCmd{} = cmd} -> cmd
      {_type, opts} when is_list(opts) -> ExecCmd.new(opts)
    end
    |> ExecCmd.add(name: equipment, notify: true)

    #  ExecCmd.add_name(point.cmd, equipment)
  end

  @doc """
  Adjusts the `Point` command params
  """
  @doc since: "0.2.5"
  def cmd_params(%Point{cmd: :default} = pt, _params), do: pt

  def cmd_params(%Point{cmd: cmd} = pt, params) do
    case cmd do
      cmd_opts when is_list(cmd_opts) -> %Point{pt | cmd: ExecCmd.new(cmd_opts)} |> cmd_params(params)
      %ExecCmd{} = ec -> %Point{pt | cmd: ExecCmd.params_adjust(ec, params)}
    end
  end

  @doc since: "0.2.1"
  def fixed_event(%Point{} = pt, opts) do
    {ref_dt, opts_rest} = Keyword.pop(opts, :datetime)
    {time_parts, _} = Keyword.split(opts_rest, @time_parts)

    %Point{pt | at: struct(ref_dt, time_parts)}
  end

  @doc since: "0.2.1"
  def less_than?(%Point{at: lhs}, %Point{at: rhs}), do: Timex.compare(lhs, rhs) <= 0

  @doc since: "0.2.1"
  def new_start(opts) when is_list(opts) do
    [{:type, :start} | opts] |> new()
  end

  @doc since: "0.2.1"
  def new_finish(opts) when is_list(opts) do
    [{:type, :finish} | opts] |> new()
  end

  @doc since: "0.2.1"
  @new_keys [:type, :sunref, :offset_ms, :cmd]
  def new(opts) do
    {fields, opts_rest} = List.flatten(opts) |> Keyword.split(@new_keys)
    {want_calc_at, calc_opts} = Keyword.pop(opts_rest, :calc_at, false)

    struct(Point, fields)
    |> then(fn point -> if(want_calc_at, do: calc_at(point, calc_opts), else: point) end)
  end

  @doc since: "0.2.1"
  def type(%Point{type: type}), do: type

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp from_asn1(pt, sunref, opts) when is_binary(sunref) do
    datetime = opts[:datetime]

    ref_dt = parse_asn1(sunref, opts)
    time_parts = Map.take(ref_dt, @time_parts_ext)

    %Point{pt | at: struct(datetime, time_parts)}
  end

  defp offset(%Point{at: at} = pt) do
    %Point{pt | at: Timex.shift(at, milliseconds: pt.offset_ms)}
  end

  defp parse_asn1(sunref, opts) do
    Timex.parse!(sunref, @asn1_format) |> Timex.to_datetime(opts[:timezone])
  end

  @regex ~r"""
  ^fixed\s(?<hour>\d\d):(?<minute>\d\d):(?<second>\d\d)$
  |
  ^(?<sunref>[a-z\s]+)$
  |
  ^(?<asn1>\d{14}.\d{1,}Z)$
  """x
  @doc since: "0.2.1"
  defp parse_sunref(sunref) when is_binary(sunref) do
    Regex.named_captures(@regex, sunref)
    |> Enum.reject(fn {_, v} -> v == "" end)
    |> rationalize_parts()
  end

  defp rationalize_parts(parts) do
    for {k, v} <- parts, into: %{} do
      case {String.to_atom(k), v} do
        {:sunref, _sunref} = kv -> kv
        {:asn1, _} = kv -> kv
        {key, val} when key in @time_parts -> {key, String.to_integer(val)}
      end
    end
  end

  defp solar_event(%Point{} = pt, opts) do
    event_opts = Keyword.take(opts, [:timezone, :datetime])

    %Point{pt | at: Solar.event(pt.sunref, event_opts)}
  end
end
