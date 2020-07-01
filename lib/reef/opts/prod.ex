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
            off: [for: "PT12M", at_cmd_finish: :off]
          ],
          topoff: [
            run_for: "PT1H",
            on: [for: "PT10M", at_cmd_finish: :off],
            off: [for: "PT1M", at_cmd_finish: :off]
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
            off: [for: "PT15M", at_cmd_finish: :off],
            repeat: true
          ]
        ],
        # sub_steps are step definitions only executed when included in
        # a step listed in steps
        sub_steps: [
          circulate: [on: [for: "PT1M", at_cmd_finish: :off]]
        ]
      ],
      clean: [off: [for: "PT2H", at_cmd_finish: :on]],
      mix_salt: [
        step_devices: [salt: :pump, stir: :pump, aerate: :air],
        steps: [
          salt: [
            on: [for: "PT45M"],
            next_step: :stir
          ],
          stir: [
            run_for: "PT1H",
            on: [for: "PT5M", at_cmd_finish: :off],
            off: [for: "PT7M", at_cmd_finish: :off],
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
            off: [for: "PT5M", at_cmd_finish: :off],
            repeat: true
          ]
        ]
      ]
    ]
  end
end
