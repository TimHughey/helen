defmodule Reef.Captain.Opts do
  @moduledoc false

  alias Helen.Module.Config

  def syntax_version, do: "2020-0710"

  def create_default_config_if_needed(module) do
    if Config.available?(module) and syntax_version_match?(module) do
      :ok
    else
      Config.create_or_update(module, default_opts(), "auto created defaults")
    end
  end

  def default_opts do
    [
      syntax_vsn: syntax_version(),
      timeout: "PT3M",
      timezone: "America/New_York",
      modes: [
        fill: [
          step_devices: [main: :rodi, topoff: :rodi, aerate: :air],
          steps: [
            main: [
              run_for: "PT5H",
              on: [for: "PT2M10S", at_cmd_finish: :off],
              aerate: :on,
              off: [for: "PT12M"]
            ],
            topoff: [
              run_for: "PT15M",
              on: [for: "PT2M", at_cmd_finish: :off],
              off: [for: "PT1M"]
            ],
            finally: [msg: {:handoff, :keep_fresh}]
          ],
          sub_steps: [
            aerate: [on: [for: "PT3M", at_cmd_finish: :off]]
          ]
        ],
        keep_fresh: [
          step_devices: [aerate: :air, circulate: :pump],
          steps: [
            aerate: [
              on: [for: "PT5M", at_cmd_finish: :off],
              circulate: :on,
              off: [for: "PT15M"],
              repeat: true
            ]
          ],
          # sub_steps are step definitions only executed when included in
          # a step listed in steps
          sub_steps: [
            circulate: [on: [for: "PT1M", at_cmd_finish: :off]]
          ]
        ],
        clean: [
          step_devices: [cleaning: :ato],
          steps: [cleaning: [off: [for: "PT1H", at_cmd_finish: :on]]]
        ],
        mix_salt: [
          step_devices: [salt: :pump, stir: :pump, aerate: :air],
          steps: [
            salt: [
              on: [for: "PT20M"]
            ],
            stir: [
              run_for: "PT30M",
              on: [for: "PT5M", at_cmd_finish: :off],
              aerate: :on,
              off: [for: "PT5M"]
            ],
            finally: [msg: {:handoff, :prep_for_change}]
          ],
          sub_steps: [
            aerate: [on: [for: "PT3M", at_cmd_finish: :off]]
          ]
        ],
        prep_for_change: [
          step_devices: [stir: :pump, match_display_tank: :none],
          steps: [
            match_display_tank: [msg: {:mixtank_temp, :active}],
            stir: [
              on: [for: "PT1M", at_cmd_finish: :off],
              off: [for: "PT5M"],
              repeat: true
            ]
          ]
        ],
        water_change: [
          step_devices: [
            air_off: :air,
            prep: :pump,
            dump_to_sewer: :pump,
            adjust_valves: :pump,
            transfer_h2o: :pump,
            final_check: :pump,
            normal_operations: :none
          ],
          steps: [
            air_off: [off: [for: "PT1S"]],
            prep: [
              off: [for: "PT30S"],
              msg: {:mixtank_temp, :standby},
              msg: {:display_temp, :standby}
            ],
            dump_to_sewer: [on: [for: "PT2M35S", at_cmd_finish: :off]],
            adjust_valves: [off: [for: "PT45S"]],
            transfer_h2o: [on: [for: "PT2M35S", at_cmd_finish: :off]],
            final_check: [off: [for: "PT10M"]],
            normal_operations: [msg: {:display_tank, :active}]
          ]
        ]
      ]
    ]
  end

  @doc """
  Reset the module options to defaults as specified in default_opts/0 and restart
  the server.
  """
  def reset_to_defaults(module) do
    Config.create_or_update(module, default_opts(), "reset by api call")
  end

  def syntax_version_match?(module) do
    opts = Config.opts(module)

    if opts[:syntax_vsn] == syntax_version(), do: true, else: false
  end

  def test_opts do
    opts = [
      syntax_vsn: syntax_version(),
      timeout: "PT3M",
      timezone: "America/New_York",
      modes: [
        fill: [
          step_devices: [main: :rodi, topoff: :rodi, aerate: :air],
          steps: [
            main: [
              run_for: "PT30S",
              on: [for: "PT2S", at_cmd_finish: :off],
              aerate: :on,
              off: [for: "PT1S", at_cmd_finish: :off]
            ],
            topoff: [
              run_for: "PT30S",
              on: [for: "PT2S", at_cmd_finish: :off],
              off: [for: "PT2S", at_cmd_finish: :off]
            ],
            finally: [msg: {:handoff, :keep_fresh}]
          ],
          sub_steps: [
            aerate: [on: [for: "PT0.5S", at_cmd_finish: :off]]
          ]
        ],
        keep_fresh: [
          step_devices: [aerate: :air, circulate: :pump],
          steps: [
            aerate: [
              on: [for: "PT4S", at_cmd_finish: :off],
              circulate: :on,
              off: [for: "PT4S", at_cmd_finish: :off],
              repeat: true
            ]
          ],
          sub_steps: [
            # sub_steps are step definitions only executed when included in
            # a step listed in steps
            circulate: [on: [for: "PT1S", at_cmd_finish: :off]]
          ]
        ],
        clean: [
          step_devices: [cleaning: :ato],
          steps: [cleaning: [off: [for: "PT2H", at_cmd_finish: :on]]]
        ],
        mix_salt: [
          step_devices: [salt: :pump, stir: :pump, aerate: :air],
          steps: [
            salt: [
              on: [for: "PT5S"]
            ],
            stir: [
              run_for: "PT10S",
              on: [for: "PT2S", at_cmd_finish: :off],
              off: [for: "PT2S", at_cmd_finish: :off],
              aerate: :on
            ],
            finally: [msg: {:handoff, :prep_for_change}]
          ],
          sub_steps: [
            aerate: [on: [for: "PT4S", at_cmd_finish: :off]]
          ]
        ],
        prep_for_change: [
          step_devices: [stir: :pump, match_display_tank: :heat],
          steps: [
            match_display_tank: [msg: {:mixtank_temp, :active}],
            stir: [
              on: [for: "PT2S", at_cmd_finish: :off],
              off: [for: "PT2S", at_cmd_finish: :off],
              repeat: true
            ]
          ]
        ],
        water_change: [
          step_devices: [
            air_off: :air,
            prep: :pump,
            dump_to_sewer: :pump,
            transfer_h2o: :pump,
            final_check: :pump,
            normal_operations: :none
          ],
          steps: [
            air_off: [off: [for: "PT11S"]],
            prep: [
              off: [for: "PT5S"],
              msg: {:mixtank_temp, :standby},
              msg: {:display_temp, :standby}
            ],
            dump_to_sewer: [on: [for: "PT30S", at_cmd_finish: :off]],
            adjust_valves: [off: [for: "PT2S"]],
            transfer_h2o: [on: [for: "PT30S", at_cmd_finish: :off]],
            final_check: [off: [for: "PT5S"]],
            normal_operations: [msg: {:display_temp, :active}]
          ]
        ]
      ]
    ]

    Config.create_or_update(module(), opts, "test opts")
  end

  defp module do
    # drop the last part of this module (e.g.) to create the name of the module
    # these opts are for
    mod_parts = Module.split(__MODULE__)
    num_parts = length(mod_parts)

    [Enum.take(mod_parts, num_parts - 1), Server]
    |> List.flatten()
    |> Module.concat()
  end
end
