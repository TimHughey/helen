defmodule Reef.Opts.Test do
  @moduledoc false

  def defaults do
    [
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
  end
end
