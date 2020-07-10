defmodule Reef.FirstMate.Opts do
  alias Helen.Module.Config
  alias Helen.Module.DB.Config, as: DB

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
      timeout: "PT1M",
      timezone: "America/New_York",
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
      timeout: "PT1M",
      timezone: "America/New_York",
      modes: [
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
    ]

    DB.create_or_update(module(), opts, "test opts")
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
