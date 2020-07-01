defmodule Reef.Opts.Test do
  @moduledoc false

  def defaults do
    [
      fill: [
        step_devices: [main: :rodi, topoff: :rodi, aerate: :air],
        steps: [
          main: [
            run_for: "PT10S",
            on: [for: "PT2S", at_cmd_finish: :off],
            aerate: :on,
            off: [for: "PT1S", at_cmd_finish: :off]
          ],
          topoff: [
            run_for: "PT10S",
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
      clean: [off: [for: "PT15S", at_cmd_finish: :on]],
      mix_salt: [
        step_devices: [salt: :pump, stir: :pump, aerate: :air],
        steps: [
          salt: [
            on: [for: "PT5S"]
          ],
          stir: [
            run_for: "PT10S",
            on: [for: "PT2S", at_cmd_finish: :off],
            aerate: :on,
            off: [for: "PT2S", at_cmd_finish: :off]
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
      ]
    ]
  end
end
