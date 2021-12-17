defmodule Carol.Program do
  use Timex
  alias __MODULE__
  alias Carol.Point

  defstruct id: :none, start: :none, finish: :none

  @type t :: %Program{id: binary(), start: Point.t(), finish: Point.t()}

  @doc """
  Analyze a `Program` calculate as needed

  ## Handles `Point` Conditions

  1. needs calculation - `at: :none`
  2. stale - both `start` and `finish` have past
  3. overnight pair - `finish` is before `start`

  ## Example
  ```
  # populated Program:
  # program = %Program{id: "some id", start: %Point{}, finish: %Point{}}

  # required options:
  # 1. datetime: YYYY-MM-DD reference for calculating at
  # 2. timezone required for Solar.event/1 or Point.fixed event/2
  opts = [datetime: %DateTime{}, timezone: "America/New_York"]

  # perform the analysis and calculate as required
  Program.analyze(program, opts)
  #=> %Program{id: "some id", start: %Point{}, finish: %Point{}}

  ```
  > Recurses until all conditions are resolved.
  """
  @doc since: "0.2.1"
  def analyze(%Program{} = program, opts) do
    dt = opts[:datetime]

    # grab the start and finish DateTime
    srt_at = program.start.at
    fin_at = program.finish.at

    # must include the original opts for next analyze
    calc_ctrl = %{accumulator: program, opts: opts}

    cond do
      srt_at == :none and fin_at == :none -> %{action: :calc}
      # NOTE: must check overnight before stale
      # overnight/1 clears fin_at and increments the ref dt to the next day
      Timex.before?(fin_at, srt_at) and same_day?(srt_at, fin_at) -> overnight(calc_ctrl)
      # are both the start and finish in the past?
      Timex.after?(dt, srt_at) and Timex.after?(dt, fin_at) -> stale(calc_ctrl)
      # all conditions are met, break from recursion
      true -> %{action: :ok}
    end
    |> Map.merge(calc_ctrl)
    # clear at only clears keys listed in %{clear: [key, ...]}
    |> clear_at()
    # calculate will only create a DateTime for at: :none
    |> calculate()
    # recursively call ourself until all conditons have been handled
    |> analyze()
  end

  # (1 of 2) all conditions met, break out of recursion
  def analyze(%{action: :ok, accumulator: accumulator}), do: accumulator

  # (2 of 2) an action was performed, call ourself again
  def analyze(%{action: _, accumulator: accumulator, opts: opts}) do
    # pass the revised program map and original opts
    analyze(accumulator, opts)
  end

  @doc """
  Analyze a list of `Program`s

  `Carol.Program.analyze/2` is invoked for each `Program` in the list
  """
  @doc since: "0.2.1"
  def analyze_all([%Program{} | _] = programs, opts) do
    for %Program{} = program <- programs do
      analyze(program, opts)
    end
    |> sort()
  end

  def analyze_all(what, _opts) when what == :none or what == [], do: []

  @doc """
  Adjust the command params for a `Program`
  """
  @doc since: "0.2.5"
  def adjust_cmd_params(programs, opts) do
    {id, opts_rest} = Keyword.pop(opts, :id)
    {params, _opts_rest} = Keyword.pop(opts_rest, :cmd_params)

    for prg <- programs, reduce: [] do
      acc ->
        case prg do
          %Program{id: ^id} -> %Program{prg | start: Point.cmd_params(prg.start, params)}
          _ -> prg
        end
        |> then(fn prg -> [prg | acc] end)
    end
  end

  @doc """
  Calculate the pair of start/finish

  > Only `%Point{at: :none}` are calculated.
  """
  @doc since: "0.2.1"
  def calculate(%{accumulator: accumulator} = calc_ctrl) do
    # use calc_opts when present, otherwise fallback to opts
    opts = calc_ctrl[:calc_opts] || calc_ctrl[:opts]

    points_map = Map.take(accumulator, [:start, :finish])

    for {_, %Point{at: :none} = point} <- points_map, reduce: accumulator do
      acc -> Point.calc_at(point, opts) |> save_point(acc)
    end
    |> then(fn acc -> %{calc_ctrl | accumulator: acc} end)
  end

  def cmd(programs, id, opts) when is_binary(id) do
    programs
    |> find(id, opts)
    |> start_point()
    |> Point.cmd(opts[:equipment])
  end

  def cmd(programs, what, opts) when what in [:active, :next] do
    programs
    |> find(what, opts)
    |> start_point()
    |> Point.cmd(opts[:equipment])
  end

  @doc since: "0.2.1"
  def cmd_for_id(id, programs, equipment)
      when is_binary(id)
      when is_list(programs)
      when is_binary(equipment) do
    for %Program{id: ^id, start: point} <- programs, reduce: :none do
      _acc -> Point.cmd(point, equipment)
    end
  end

  @doc """
  Find a `Program`

  ## Examples
  ```
  # requires :datetime in opts
  opts = [datetime: Timex.now("America/New_York")])]

  # list of Program
  program_list = [%Program{}, ...)

  # find the active Program
  Program.find(program_list, :active, opts)
  #=> returns the found Point or :none

  # find the next Program
  Program.find(program_list, :next, opts)
  #=> returns the found Point or :none

  # find a Program using a function boolean result
  compare_fn = fn sat, fat -> DateTime.compare(sat, fat) == :eq end
  Program.find(program_list, compare_fn, opts)

  ```
  """
  @doc since: "0.2.1"
  def find(program_list, atom_or_function, opts \\ [])

  def find([%Program{} | _] = program_list, func, opts) when is_function(func) do
    for program <- program_list, reduce: :none do
      # found a program, stop
      %Program{} = program -> program
      # search for a true from the function check
      acc -> if func.(program, opts), do: program, else: acc
    end
  end

  def find(prgs, what, opts) when what in [:active, :next] and is_list(prgs) do
    case what do
      :active -> find(prgs, &active?/2, opts)
      :next -> find(prgs, &next?/2, opts)
    end
  end

  def find(prgs, id, _opts) when is_binary(id) and is_list(prgs) do
    find(prgs, fn prg, _opts -> prg.id == id end)
  end

  def finish(prgs, id) do
    for program <- prgs do
      case program do
        %Program{id: ^id} -> clear_points(program)
        _ -> program
      end
    end
  end

  @doc """
  Creates a list of computed values for each `Program` in the list

  > Decouples `Program` for use downstream

  ## Example
  ```
  # flattens a Program list into a series of lists containing computed values
  # for fields that depend on a specific datetime
  [%Program{id: "Sunset", start: %Point{}, finish: %Point}, ...]
  #=> [[id: "Sunset", type: :start, ms: 10_000], ...]

  ```
  """
  @doc since: "0.2.1"
  def flatten([%Program{} | _] = programs, opts) do
    for %Program{id: id} = program <- programs do
      cond do
        active?(program, opts) -> [type: :active, ms: run_ms(program, opts)]
        next?(program, opts) -> [type: :next, ms: queue_ms(program, opts)]
        true -> []
      end
      |> List.flatten()
      |> then(fn fields -> [{:id, id} | fields] end)
    end
  end

  def flatten(_, _opts), do: []

  @doc """
  Creates a `Program` using the start and finish `Point`

  Example
  # accepts: [%Point{type: :start, ..}, %Point{type: :finish, ...}]
  [
    [id: "Sunrise", start: %Point{}, finish: %Point{}],
    [id: "Sunset", start: %Point{}, finish: %Point{}]
  ]
  |> Program.new([id: "Sunrise"])
  #=> %Program{id: "Sunrise", start: %Point{type: :start, ...}, finish: %Point{type: :finish, ...}}

  ```
  """
  @doc since: "2.1.0"
  def new([%Point{type: :start}, %Point{type: :finish}] = pt_list, opts) when is_list(opts) do
    accumulator = struct(Program, opts)

    for %Point{} = pt <- pt_list, reduce: accumulator do
      acc -> pt |> save_point(acc)
    end
  end

  def queue_ms(%Program{start: start}, opts) do
    dt = opts[:datetime]

    duration_ms(start.at, dt)
  end

  def run_ms(%Program{start: start, finish: finish}, opts) do
    now = opts[:datetime]

    # calculate the millis already past since the program start time
    consumed_ms = Timex.diff(now, start.at, :millisecond)

    # revise the start time to account for consumed millis
    revised_start_at = Timex.shift(start.at, milliseconds: consumed_ms)

    # now calculate the remaining run millis
    duration_ms(finish.at, revised_start_at)
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp apply_fields(fields, program), do: struct(program, fields)

  defp active?(program, opts) do
    dt = opts[:datetime]

    Timex.between?(dt, program.start.at, program.finish.at, inclusive: :start)
  end

  defp clear_points(%Program{start: start, finish: finish} = program) do
    [start: Point.clear_at(start), finish: Point.clear_at(finish)]
    |> apply_fields(program)
  end

  defp clear_at(%{accumulator: accumulator, clear: clear_keys} = calc_ctrl) do
    # grab the program to clear
    points_map = Map.take(calc_ctrl.accumulator, clear_keys)

    for {_, point} <- points_map, reduce: accumulator do
      acc -> Point.clear_at(point) |> save_point(acc)
    end
    |> then(fn acc -> %{calc_ctrl | accumulator: acc} end)
  end

  defp clear_at(calc_ctrl), do: calc_ctrl

  def duration_ms(dt1, dt2) do
    Timex.diff(dt1, dt2, :duration)
    |> Duration.abs()
    |> Duration.to_milliseconds(truncate: true)
  end

  defp less_than?(lhs, rhs), do: Point.less_than?(lhs.start, rhs.start)

  defp next?(program, opts) do
    dt = opts[:datetime]

    Timex.before?(dt, program.start.at) and Timex.before?(dt, program.finish.at)
  end

  defp next_day(%DateTime{} = dt, opts) do
    Keyword.replace(opts, :datetime, dt) |> next_day()
  end

  defp next_day(opts) do
    opts[:datetime]
    |> Timex.shift(days: 1)
    |> then(fn datetime -> Keyword.replace(opts, :datetime, datetime) end)
  end

  defp overnight(%{accumulator: accumulator, opts: opts}) do
    start_at = accumulator.start.at
    %{action: :calc, clear: [:finish], calc_opts: next_day(start_at, opts)}
  end

  # defp pending?(ref_dt, srt_at, fin_at) do
  #   Timex.before?(srt_at, ref_dt) and Timex.before?(fin_at, ref_dt) and same_day?(srt_at, fin_at)
  # end

  defp same_day?(dt1, dt2), do: Timex.day(dt1) == Timex.day(dt2)

  defp save_point(%Point{} = pt, %Program{} = x) do
    struct(x, [{Point.type(pt), pt}])
  end

  defp start_point(%Program{start: pt}), do: pt

  defp sort([%Program{} | _] = point_list), do: Enum.sort(point_list, &less_than?/2)

  defp stale(%{opts: opts}) do
    %{action: :calc, clear: [:start, :finish], calc_opts: next_day(opts)}
  end
end
