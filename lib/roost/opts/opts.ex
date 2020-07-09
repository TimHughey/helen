defmodule Roost.Opts do
  alias Helen.Module.Config

  def syntax_version, do: 1

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
      cmd_definitions: [
        dance_fade: %{
          name: "roost dance fade",
          random: %{
            min: 128,
            max: 2048,
            primes: 35,
            step_ms: 55,
            step: 1,
            priority: 7
          }
        },
        closed_fade: %{
          name: "roost closed fade",
          random: %{
            min: 64,
            max: 768,
            primes: 35,
            step_ms: 55,
            step: 1,
            priority: 7
          }
        }
      ],
      devices: [
        disco_ball: "roost disco ball",
        el_wire: "roost el wire",
        el_wire_entry: "roost el wire entry",
        lights_one: "roost lights sound one",
        lights_three: "roost lights sounds three",
        led_forest: "roost led forest"
      ],
      modes: [
        dance_with_me: [
          steps: [
            spin_up: [
              led_forest: [random: :dance_fade],
              disco_ball: [duty: 0.7],
              el_wire: [duty: 0.5],
              el_wire_entry: [duty: 0.5],
              on: [:lights_one, :lights_three],
              send_msg: [after: "PT1M", msg: {:via_msg, :slow_disco_ball}]
            ],
            slow_disco_ball: [
              via_msg: true,
              disco_ball: [duty: 0.63]
            ],
            dance: [hold_mode: true]
          ]
        ],
        leaving: [
          steps: [
            house_lights: [
              off: [:disco_ball, :el_wire, :lights_one, :lights_three],
              on: [:led_forest, :el_wire_entry],
              send_msg: [after: "PT10M", msg: {:worker_mode, :closed}]
            ],
            exiting: [hold_mode: true]
          ]
        ],
        closed: [
          steps: [
            turn_down_lights: [
              off: [:el_wire_entry],
              led_forest: [random: :closed_fade]
            ],
            closed: [hold_mode: true]
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

    if opts[:syntax_version] == syntax_version(), do: true, else: false
  end

  def test_opts do
    opts = []

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
