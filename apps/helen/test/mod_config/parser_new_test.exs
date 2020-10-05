defmodule HelenModConfigParserTest do
  @moduledoc false

  alias Helen.ModConfig.Parser.New, as: Parser

  use ExUnit.Case

  @moduletag :new_parser

  setup_all do
    %{}
  end

  setup context do
    case context do
      %{snippet: snippet} when is_binary(snippet) ->
        assert {:ok, parsed} = Parser.parse(snippet)

        put_in(context, [:parsed], parsed)

      context ->
        context
    end
  end

  @tag snippet: """
       base {
         syntax_vsn "2020-09-03"
         worker_name "captain"
         description "reef captain"
         timeout PT5M
         timezone "America/New_York"
         first_mode fill
       }
       """
  test "can parse the base section", context do
    parsed = context[:parsed]

    base_defs = get_in(parsed, [:base])
    assert is_list(base_defs)

    assert [
             syntax_vsn: "2020-09-03",
             worker_name: "captain",
             description: "reef captain",
             timeout: {:duration, "PT5M"},
             timezone: "America/New_York",
             first_mode: :fill
           ] === base_defs
  end

  @tag snippet: """
       base {
         syntax_vsn "2020-09-03"
         worker_name "captain"
         description "reef captain"
         timeout PT5M
         timezone "America/New_York"
         first_mode fill
       }

       workers {
         pump "mixtank pump"
         air "mixtank air"
       }
       """
  test "can parse two sections", context do
    base_defs = get_in(context, [:parsed, :base])
    assert is_list(base_defs)

    worker_defs = get_in(context, [:parsed, :workers])
    assert is_list(worker_defs)
  end

  @tag snippet: """
       mode fill {
         next_mode clean
         sequence alpha, beta, gamma

         step all_stop for PT5M10S {
           sleep PT1S
           tell mixtank_heater standby
           lights duty 0.7
           all on; rodi off
           off air, pump, rodi
           pump on for PT10M
           air on for PT5M10S then off
           pump off for PT10M then off nowait
         }
       }
       """
  test "can parse a mode section", context do
    mode = get_in(context, [:parsed, :modes, :fill])
    mode_details = get_in(mode, [:details])

    assert is_map(mode)
    assert is_list(mode_details)

    step = get_in(mode_details, [:step])

    assert is_map(step)

    {step_meta, step_details} = Map.split(step, [:name, :for])

    assert %{name: :all_stop, for: "PT5M10S"} == step_meta

    actions = get_in(step_details, [:actions])

    assert is_list(actions)

    assert [
             %{cmd: :sleep, worker_name: nil, for: "PT1S"},
             %{cmd: :tell, worker_name: :mixtank_heater, mode: :standby},
             %{cmd: :duty, worker_name: :lights, number: 0.7},
             %{cmd: :on, worker_name: :all},
             %{cmd: :off, worker_name: :rodi},
             %{cmd: :off, worker_name: [:air, :pump, :rodi]},
             %{cmd: :on, for: "PT10M", worker_name: :pump},
             %{cmd: :on, for: "PT5M10S", then: :off, worker_name: :air},
             %{
               cmd: :off,
               for: "PT10M",
               nowait: true,
               then: :off,
               worker_name: :pump
             }
           ] === actions
  end

  @tag snippet: """
       mode alpha {
         next_mode beta
         sequence one, two

         step one { all off }
         step two { all on }
       }

       mode beta {
         sequence one, repeat

         step one { sleep PT10S }
       }
       """
  test "can parse two modes", context do
    parsed = context[:parsed]

    assert is_map(parsed[:modes])
    assert Map.keys(parsed[:modes]) == [:alpha, :beta]
  end

  @tag snippet: """
       command dance_fade "roost dance fade" random {
           min 128, max 2048, primes 35, step_ms 55, step 13, priority 7
       }
       """
  test "can parse a command definition section", context do
    command = get_in(context, [:parsed, :commands, :dance_fade])
    assert is_map(command)

    assert command[:cmd] == :dance_fade
    assert command[:name] == "roost dance fade"
    assert command[:type] == :random

    details = command[:details]
    assert is_list(details)

    assert [min: 128, max: 2048, primes: 35, step_ms: 55, step: 13, priority: 7] ==
             details
  end

  test "can parse Reef Captain default opts" do
    alias Reef.Captain.Opts

    result = Opts.default_new_opts() |> Parser.parse()

    assert {:ok, parsed} = result
    assert is_map(parsed)
  end

  test "can parse Reef FirstMate default opts" do
    alias Reef.FirstMate.Opts

    result = Opts.default_new_opts() |> Parser.parse()

    assert {:ok, parsed} = result
    assert is_map(parsed)
  end

  test "can parse Roost default opts" do
    alias Roost.Opts

    result = Opts.default_new_opts() |> Parser.parse()

    assert {:ok, parsed} = result
    assert is_map(parsed)
  end
end
