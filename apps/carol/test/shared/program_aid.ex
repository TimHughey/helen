defmodule Carol.ProgramAid do
  alias Alfred.ExecCmd
  alias Carol.{Point, Program}

  @tz "America/New_York"
  @cmd_opts [echo: true, notify: true]
  @cmd_on %ExecCmd{cmd: "on"} |> ExecCmd.add(@cmd_opts)

  @point_base [cmd: @cmd_on]
  @civil_set "civil twilight set"
  @civil_rise "civil twilight rise"

  @single [:future, :live, :overnight, :past, :stale]
  @multi [:future_programs, :live_programs, :live_quick_programs, :programs]
  def add(%{program_add: what, opts: opts, ref_dt: ref_dt}) do
    opts = [{:ref_dt, ref_dt} | opts]

    case what do
      x when x in @single -> add_one(x, opts)
      x when x in @multi -> add_multi(x, opts)
    end
    |> wrap_program()
  end

  def add(_ctx), do: :ok

  # add multiple programs
  # returns: [ %Program{}, ...]

  def add_multi(:future_programs, opts) do
    # NOTE: use :past here, Program.analyze/2 recalculates for next day
    for type <- [:future, :past], do: add_one(type, opts)
  end

  def add_multi(:live_programs, opts) do
    for type <- [:future, :live, :past] do
      add_one(type, opts)
    end
  end

  def add_multi(:live_quick_programs, opts) do
    for {type, shift_opts} <- [
          live: [finish_shift: [milliseconds: 100]],
          live: [start_shift: [milliseconds: 500], finish_shift: [milliseconds: 100]],
          past: []
        ] do
      add_one(type, shift_opts ++ opts)
    end
  end

  def add_multi(:programs, opts) do
    for type <- [:future, :overnight, :stale], do: add_one(type, opts)
  end

  # add one program
  # returns: %{program: %Program{}}

  def add_one(:future, _opts) do
    [start: make_fixed(:future, hours: 1), finish: make_fixed(:future, hours: 2)]
    |> make_program(id: "Future")
  end

  def add_one(:live, opts) do
    {start_shift, opts_rest} = Keyword.pop(opts, :start_shift, [])
    {finish_shift, _opts_rest} = Keyword.pop(opts_rest, :finish_shift, seconds: 10)

    [start: make_fixed(:now, start_shift ++ opts), finish: make_fixed(:now, finish_shift ++ opts)]
    |> make_program(id: "Live")
  end

  def add_one(:overnight, _opts) do
    [start: @civil_set, finish: @civil_rise]
    |> make_program(id: "Overnight")
  end

  def add_one(:past, _opts) do
    [start: make_fixed(:past, hours: 13), finish: make_fixed(:past, hours: 12)]
    |> make_program(id: "Past")
  end

  def add_one(:stale, _opts) do
    [start: make_fixed(:past, hours: 6), finish: make_fixed(:past, hours: 7)]
    |> make_program(id: "Stale")
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  # defp make_fixed({_hour, _minute} = time_tuple) do
  #   Tuple.append(time_tuple, 0) |> make_fixed()
  # end

  defp make_fixed({_hour, _minute, _second} = time_tuple) do
    for part <- Tuple.to_list(time_tuple), reduce: [] do
      parts ->
        # no seperator for the first part
        sep = if(parts != [], do: [":"], else: [])
        part_bin = Integer.to_string(part) |> String.pad_leading(2, "0")
        [parts | [sep, part_bin]]
    end
    |> then(fn parts -> ["fixed ", parts] end)
    |> IO.iodata_to_binary()
  end

  # defp make_fixed(what, opts \\ [])

  @shift_opts [:days, :hours, :minutes, :seconds, :milliseconds, :microseconds]
  defp make_fixed(:now, opts) do
    {ref_dt, opts_rest} = Keyword.pop(opts, :ref_dt)
    {shift_opts, _opts_rest} = Keyword.split(opts_rest, @shift_opts)

    Timex.shift(ref_dt, shift_opts) |> to_asn1()
  end

  defp make_fixed(what, opts) when what in [:future, :past] do
    {dt, shift_opts} = Keyword.pop(opts, :datetime, Timex.now(@tz))

    shift_opts = if(shift_opts == [], do: [minutes: 5], else: shift_opts)

    case what do
      :future -> shift_opts |> shift_adjust(&</2)
      :past -> shift_opts |> shift_adjust(&>/2)
    end
    |> then(fn shift_opts -> Timex.shift(dt, shift_opts) end)
    |> then(fn dt -> make_fixed({dt.hour, dt.minute, dt.second}) end)
  end

  defp make_point(opts) do
    [opts | @point_base] |> List.flatten() |> Point.new()
  end

  defp make_program(point_tuples, opts) do
    for {type, sunref} <- point_tuples do
      [type: type, sunref: sunref]
      |> make_point()
    end
    |> Program.new(opts)
  end

  defp shift_adjust(opts, compare_fn) do
    for {unit, val} <- opts, into: [] do
      val = if(compare_fn.(val, 0), do: val * -1, else: val)

      {unit, val}
    end
  end

  defp to_asn1(%DateTime{} = dt), do: Timex.format!(dt, "{ASN1:GeneralizedTime:Z}")

  defp wrap_program(%Program{} = program),
    do: %{program: program}

  defp wrap_program([%Program{} | _] = programs), do: %{programs: programs}
end
