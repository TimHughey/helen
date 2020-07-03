defmodule Reef.FirstMate.Opts do
  alias Helen.Module.Config
  alias Helen.Module.DB.Config, as: DB

  def create_default_config_if_needed do
    if Config.available?(Reef.FirstMate) do
      nil
    else
      opts = [
        timeout: "PT1M",
        clean: [
          step_devices: [ato_disable: :ato, ato_enable: :ato],
          steps: [
            ato_disable: [
              run_for: "PT1H10S",
              off: [for: "PT1M", at_cmd_finish: :off]
            ],
            ato_enable: [
              run_for: "PT11S",
              on: [for: "PT10S", at_cmd_finish: :on]
            ]
          ]
        ],
        water_change_start: [
          step_devices: [ato_disable: :ato, ato_enable: :ato],
          steps: [
            ato_disable: [
              run_for: "PT3H10S",
              off: [for: "PT1M", at_cmd_finish: :off]
            ],
            ato_enable: [
              run_for: "PT11S",
              on: [for: "PT10S", at_cmd_finish: :on]
            ]
          ]
        ],
        water_change_finish: [
          step_devices: [ato_disable: :ato, ato_enable: :ato],
          steps: [
            ato_disable: [
              run_for: "PT30M10S",
              off: [for: "PT30M", at_cmd_finish: :off]
            ],
            ato_enable: [
              run_for: "PT11S",
              on: [for: "PT10S", at_cmd_finish: :on]
            ]
          ]
        ],
        normal_operations: [
          steps: [
            ato_enable: [
              run_for: "PT11S",
              on: [for: "PT10S", at_cmd_finish: :on]
            ]
          ]
        ]
      ]

      DB.create_or_update(Reef.FirstMate, opts, "auto created defaults")
    end
  end

  def test_opts do
    opts = [
      timeout: "PT1M",
      clean: [
        step_devices: [ato_disable: :ato, ato_enable: :ato],
        steps: [
          ato_disable: [
            run_for: "PT11S",
            off: [for: "PT1S", at_cmd_finish: :off]
          ],
          ato_enable: [
            run_for: "PT3S",
            on: [for: "PT1S", at_cmd_finish: :on]
          ]
        ]
      ],
      water_change_start: [
        step_devices: [ato_disable: :ato, ato_enable: :ato],
        steps: [
          ato_disable: [
            run_for: "PT11S",
            off: [for: "PT1S", at_cmd_finish: :off]
          ],
          ato_enable: [
            run_for: "PT3S",
            on: [for: "PT1S", at_cmd_finish: :on]
          ]
        ]
      ],
      water_change_finish: [
        step_devices: [ato_disable: :ato, ato_enable: :ato],
        steps: [
          ato_disable: [
            run_for: "PT10S",
            off: [for: "PT1S", at_cmd_finish: :off]
          ],
          ato_enable: [
            run_for: "PT11S",
            on: [for: "PT3S", at_cmd_finish: :on]
          ]
        ]
      ],
      normal_operations: [
        steps: [
          ato_enable: [
            run_for: "PT11S",
            on: [for: "PT10S", at_cmd_finish: :on]
          ]
        ]
      ]
    ]

    DB.create_or_update(Reef.FirstMate, opts, "test opts")
  end
end
