defmodule HelenConfigParserTest do
  @moduledoc false

  alias Helen.Config.Parser

  use ExUnit.Case
  import ExUnit.CaptureLog

  test "can detect and track unmatched lines" do
    snippet = "! $"

    assert capture_log(fn ->
             opts = Parser.parse(snippet)

             assert %{
                      parser: %{
                        unmatched: %{count: 1, lines: lines},
                        match: %{
                          context: :unmatched,
                          stmt: :unmatched,
                          norm: :unmatched,
                          captures: %{}
                        }
                      }
                    } = opts

             assert length(lines) == 1
           end) =~ "unmatched"
  end

  test "can match comment line" do
    comment = "# this is a comment"

    opts = Parser.parse(comment)

    assert %{
             parser: %{
               comments: %{count: 1, lines: lines},
               unmatched: %{lines: [], count: 0},
               match: %{
                 context: :top_level,
                 stmt: :comments,
                 norm: :key_binary,
                 captures: %{comment: comment}
               }
             }
           } = opts

    assert length(lines) == 1
    assert is_binary(comment)
    assert comment == "this is a comment"
  end

  test "can match multiple empty lines" do
    empties = """

    """

    opts = Parser.parse(empties)

    assert %{
             parser: %{
               empties: %{count: 2, lines: [1, 2]},
               unmatched: %{lines: [], count: 0},
               match: %{
                 context: :top_level,
                 stmt: :empties,
                 norm: :key_binary,
                 captures: %{}
               }
             }
           } = opts
  end

  test "can match a section definition" do
    section_def = "modes"

    opts = Parser.parse(section_def)

    assert %{
             parser: %{
               modes: nil,
               match: %{
                 context: :top_level,
                 stmt: :section_def,
                 norm: :key_atom,
                 captures: %{section: :modes}
               },
               unmatched: %{lines: [], count: 0}
             },
             config: %{modes: %{}}
           } = opts
  end

  test "can set base config" do
    snippet = """
    # start of test
    base
      syntax_vsn '2020-08-17'
      timezone 'America/New_York'
      timeout PT1M
      start_mode all_stop
      first_mode fill
    """

    opts = Parser.parse(snippet)

    assert %{
             parser: %{unmatched: %{lines: [], count: 0}},
             config: %{
               base: %{
                 syntax_vsn: "2020-08-17",
                 timezone: "America/New_York",
                 timeout: timeout,
                 start_mode: :all_stop,
                 first_mode: :fill
               }
             }
           } = opts

    assert is_struct(timeout)
  end

  test "cam parse devices" do
    snippet = """
    devices
      mixtank_air       gen_device
      mixtank_pump      gen_device
      mixtank_heat      temp_server
      display_ato       gen_device
      display_heat      temp_server
      acclimation_pump  'acclimation'
    """

    opts = Parser.parse(snippet)

    assert %{
             parser: %{context: :devices, unmatched: %{lines: [], count: 0}},
             config: %{
               devices: %{
                 mixtank_air: :gen_device,
                 mixtank_pump: :gen_device,
                 mixtank_heat: :temp_server,
                 display_ato: :gen_device,
                 display_heat: :temp_server,
                 acclimation_pump: "acclimation"
               }
             }
           } = opts
  end

  test "can detect and create a mode" do
    snippet = """
    modes
      fill
        next_mode keep_fresh
        sequence at_start main topoff finally
    """

    opts = Parser.parse(snippet)

    assert %{
             parser: %{
               context: :modes,
               modes: :fill,
               unmatched: %{lines: [], count: 0}
             },
             config: %{
               modes: %{
                 fill: %{
                   next_mode: :keep_fresh,
                   sequence: [:at_start, :main, :topoff, :finally]
                 }
               }
             }
           } = opts
  end

  test "can detect the mode steps section" do
    snippet = """
    modes
      fill
        steps
    """

    opts = Parser.parse(snippet)

    assert %{
             parser: %{
               context: :steps,
               modes: :fill,
               steps: nil,
               unmatched: %{lines: [], count: 0}
             }
           } = opts
  end

  test "can detect and create a mode step (basic)" do
    snippet = """
    modes
      fill
        steps
          at_start
    """

    opts = Parser.parse(snippet)

    assert %{
             parser: %{
               context: :actions,
               modes: :fill,
               steps: :at_start,
               actions: nil,
               unmatched: %{lines: [], count: 0}
             },
             config: %{modes: %{fill: %{steps: %{at_start: %{actions: []}}}}}
           } = opts
  end

  test "can detect and create a mode step (with for duration)" do
    snippet = """
    modes
      fill
        steps
          long_step for PT2H
    """

    opts = Parser.parse(snippet)

    assert %{
             parser: %{
               context: :actions,
               modes: :fill,
               steps: :long_step,
               actions: nil,
               unmatched: %{lines: [], count: 0}
             },
             config: %{
               modes: %{
                 fill: %{steps: %{long_step: %{run_for: duration, actions: []}}}
               }
             }
           } = opts

    assert %_{seconds: 7200} = duration
  end

  test "can detect and add actions to a step within a mode" do
    snippet = """
    modes
      fill
        sequence long_step
        steps
          long_step for PT2H
            sleep PT10S
            tell first_mate standby
            all off
            air off
            pump off PT1M
            air on PT5M then off
            pump on PT3M then off nowait
    """

    opts = Parser.parse(snippet)

    assert %{
             parser: %{
               context: :actions,
               modes: :fill,
               steps: :long_step,
               unmatched: %{lines: [], count: 0}
             },
             config: %{
               modes: %{
                 fill: %{
                   steps: %{
                     long_step: %{
                       run_for: duration,
                       actions: [
                         %{sleep: sleep_duration},
                         %{tell: %{device: :first_mate, msg: :standby}},
                         %{all: :off},
                         %{device: :air, cmd: :off},
                         %{
                           device: :pump,
                           cmd: :off,
                           for: cmd_duration1,
                           wait: true
                         },
                         %{
                           device: :air,
                           cmd: :on,
                           for: cmd_duration2,
                           then_cmd: :off,
                           wait: true
                         },
                         %{
                           device: :pump,
                           cmd: :on,
                           for: cmd_duration_nowait,
                           then_cmd: :off,
                           wait: false
                         }
                       ]
                     }
                   }
                 }
               }
             }
           } = opts

    assert %_{seconds: 7200} = duration
    assert %_{seconds: 10} = sleep_duration
    assert %_{seconds: 60} = cmd_duration1
    assert %_{seconds: 300} = cmd_duration2
    assert %_{seconds: 180} = cmd_duration_nowait
  end

  test "can detect and create multiple steps in a mode" do
    snippet = """
    modes
      fill
        next_mode none
        steps
          long_step for PT2H
            sleep PT10S
            tell first_mate standby
            all off
            on dev1 dev2 dev3

          finally
            air off
            pump off PT1M
            air on PT5M then off
            pump on PT3M then off nowait
            lights duty 0.7
            lights2 dance_fade
    """

    opts = Parser.parse(snippet)

    assert %{
             parser: %{
               context: :actions,
               modes: :fill,
               steps: :finally,
               unmatched: %{lines: [], count: 0}
             },
             config: %{
               modes: %{
                 fill: %{
                   next_mode: :none,
                   steps: %{
                     long_step: %{
                       run_for: duration,
                       actions: [
                         %{sleep: sleep_duration},
                         %{tell: %{device: :first_mate, msg: :standby}},
                         %{all: :off},
                         %{cmd: :on, device: [:dev1, :dev2, :dev3]}
                       ]
                     },
                     finally: %{
                       actions: [
                         %{device: :air, cmd: :off, float: nil},
                         %{
                           device: :pump,
                           cmd: :off,
                           for: cmd_duration1,
                           wait: true
                         },
                         %{
                           device: :air,
                           cmd: :on,
                           for: cmd_duration2,
                           then_cmd: :off,
                           wait: true
                         },
                         %{
                           device: :pump,
                           cmd: :on,
                           for: cmd_duration_nowait,
                           then_cmd: :off,
                           wait: false
                         },
                         %{device: :lights, cmd: :duty, float: 0.7},
                         %{device: :lights2, cmd: :dance_fade}
                       ]
                     }
                   }
                 }
               }
             }
           } = opts

    assert %_{seconds: 7200} = duration
    assert %_{seconds: 10} = sleep_duration
    assert %_{seconds: 60} = cmd_duration1
    assert %_{seconds: 300} = cmd_duration2
    assert %_{seconds: 180} = cmd_duration_nowait
  end

  test "can detect and create multiple modes" do
    snippet = """
    modes
      fill
        sequence long_step finally
        steps
          long_step for PT2H
            sleep PT10S
            tell first_mate standby
            all off

          finally
            air off
            pump off PT1M
            air on PT5M then off
            pump on PT3M then off nowait

      normal_operations
        sequence first second
        steps
          first
            sleep PT10S
          second
            sleep PT1M
    """

    opts = Parser.parse(snippet)

    assert %{
             parser: %{
               context: :actions,
               modes: :normal_operations,
               steps: :second,
               unmatched: %{lines: [], count: 0}
             },
             config: %{
               modes: %{
                 fill: %{},
                 normal_operations: %{}
               }
             }
           } = opts
  end

  test "can get actions regex" do
    assert is_list(Parser.Regex.regex(:actions))
  end

  test "can detect and create cmd_definitions" do
    snippet = """
    cmd_definitions
      dance_fade
        name 'roost dance fade'
        random
          min 128
          max 2048
          primes 35
          step_ms 55
          step 7
          priority 7
    """

    opts = Parser.parse(snippet)

    assert %{
             parser: %{
               context: :cmd_definitions,
               unmatched: %{lines: [], count: 0}
             },
             config: %{
               cmd_definitions: %{
                 dance_fade: %{
                   name: "roost dance fade",
                   type: :random,
                   min: 128,
                   max: 2048,
                   primes: 35,
                   step_ms: 55,
                   step: 7,
                   priority: 7
                 }
               }
             }
           } = opts
  end

  test "the truth will set you free" do
    assert true
  end
end
