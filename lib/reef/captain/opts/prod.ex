defmodule Reef.Opts.Prod do
  @moduledoc false

  def defaults do
    [
      fill: [
        step_devices: [main: :rodi, topoff: :rodi, aerate: :air],
        steps: [
          main: [
            run_for: "PT7H",
            on: [for: "PT2M10S", at_cmd_finish: :off],
            aerate: :on,
            off: [for: "PT12M"]
          ],
          topoff: [
            run_for: "PT1H",
            on: [for: "PT10M", at_cmd_finish: :off],
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
            on: [for: "PT30M"]
          ],
          stir: [
            run_for: "PT1H",
            on: [for: "PT5M", at_cmd_finish: :off],
            off: [for: "PT7M"],
            aerate: :on
          ],
          finally: [msg: {:handoff, :prep_for_change}]
        ],
        sub_steps: [
          aerate: [on: [for: "PT5M", at_cmd_finish: :off]]
        ]
      ],
      prep_for_change: [
        step_devices: [stir: :pump, match_display_tank: :heat],
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
          transfer_h2o: :pump,
          final_check: :pump,
          normal_operations: :none
        ],
        steps: [
          air_off: [off: [for: "PT10S"]],
          prep: [
            off: [for: "PT30S"],
            msg: {:mixtank_temp, :standby},
            msg: {:display_temp, :standby}
          ],
          dump_to_sewer: [on: [for: "PT2M35S", at_cmd_finish: :off]],
          adjust_valves: [off: [for: "PT2M"]],
          transfer_h2o: [on: [for: "PT2M35S", at_cmd_finish: :off]],
          final_check: [off: [for: "PT10M"]],
          normal_operations: [msg: {:display_tank, :active}]
        ]
      ]
    ]
  end
end
