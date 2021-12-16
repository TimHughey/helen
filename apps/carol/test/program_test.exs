defmodule CarolProgramTest do
  use ExUnit.Case, async: true
  use Should

  alias Alfred.ExecCmd
  alias Carol.Program

  @moduletag carol: true, carol_program: true

  setup [:opts_add, :program_add]

  @tz "America/New_York"

  defmacro assert_program(ctx) do
    quote location: :keep, bind_quoted: [ctx: ctx] do
      ref_dt = ctx.ref_dt

      program =
        ctx
        |> Should.Be.Map.with_key(:program)
        |> Program.analyze(ctx.opts)
        |> Should.Be.struct(Program)

      if(is_nil(ctx[:dont_check][:start_at])) do
        Should.Be.DateTime.greater(program.start.at, ref_dt)
      end

      Should.Be.DateTime.greater(program.finish.at, ref_dt)
      Should.Be.DateTime.greater(program.finish.at, program.start.at)

      # return the program for further use
      program
    end
  end

  defmacro assert_program_has_id(program, id) do
    quote location: :keep, bind_quoted: [program: program, id: id] do
      program
      |> Should.Be.Struct.with_all_key_value(Program, id: id)

      # return the program
      program
    end
  end

  defmacro assert_programs(ctx, count) do
    quote location: :keep, bind_quoted: [ctx: ctx, count: count] do
      ctx
      |> Should.Be.Map.with_key(:programs)
      |> Should.Be.List.with_length(count)
      |> Program.analyze_all(ctx.opts)
      |> Should.Be.List.of_structs(Program)

      # returns list of programs
    end
  end

  describe "Carol.Program.analyze/2" do
    @tag program_add: :future
    test "populates %Point{at: :none}", ctx do
      assert_program(ctx)
    end

    @tag program_add: :past
    test "adjusts stale start/finish to the next day", ctx do
      assert_program(ctx)
    end

    # NOTE: :overnight program uses Solar.events so don't check
    # the start time against the reference datatime
    @tag program_add: :overnight
    test "handles overnight", ctx do
      assert_program(ctx)
    end
  end

  describe "Carol.Program.analyze_all/2" do
    @tag program_add: :programs
    test "process a list of Program and sorts", ctx do
      assert_programs(ctx, 3)
    end
  end

  describe "Carol.Program.find/3" do
    @tag program_add: :live_programs
    test "returns active program", ctx do
      assert_programs(ctx, 3)
      |> Program.find(:active, datetime: Timex.now(@tz))
      |> assert_program_has_id("Live")
    end

    @tag program_add: :future_programs
    test "returns next program", ctx do
      assert_programs(ctx, 2)
      |> Program.find(:next, datetime: Timex.now(@tz))
      |> assert_program_has_id("Future")
    end

    @tag program_add: :live_programs
    test "returns program for id", ctx do
      assert_programs(ctx, 3)
      |> Program.find("Live")
      |> assert_program_has_id("Live")
    end
  end

  describe "Carol.Program" do
    @tag program_add: :live_programs
    test "calculates the run milliseconds for active program", ctx do
      assert_programs(ctx, 3)
      |> Program.find(:active, datetime: ctx.opts[:datetime])
      |> Program.run_ms(datetime: Timex.now(@tz))
      |> Should.Be.Integer.positive()
    end

    @tag program_add: :live_programs
    test "calculates the queue milliseconds", ctx do
      assert_programs(ctx, 3)
      |> Program.find(:next, datetime: Timex.now(@tz))
      |> Program.queue_ms(ctx.opts)
      |> Should.Be.Integer.positive()
    end
  end

  describe "Carol.Program.cmd/3" do
    @tag program_add: :live_programs
    test "returns cmd for active program", ctx do
      assert_programs(ctx, 3)
      |> Program.cmd(:active, ctx.opts)
      |> Should.Be.Struct.with_all_key_value(ExecCmd, name: ctx.opts[:equipment])
    end

    @tag program_add: :live_programs
    test "returns cmd for next program", ctx do
      assert_programs(ctx, 3)
      |> Program.cmd(:next, ctx.opts)
      |> Should.Be.Struct.with_all_key_value(ExecCmd, name: ctx.opts[:equipment])
    end
  end

  describe "Carol.Program.playlist/2" do
    @tag program_add: :live_programs
    test "process a list of Program and sorts", ctx do
      assert_programs(ctx, 3)
    end
  end

  def dump([%Program{} | _] = programs) do
    for program <- programs do
      """
      ID: #{program.id}
         #{inspect(program.start.at)}
         #{inspect(program.finish.at)}
      """
      |> IO.puts()
    end
  end

  defp opts_add(ctx), do: Carol.OptsAid.add(ctx)
  defp program_add(ctx), do: Carol.ProgramAid.add(ctx)
end
