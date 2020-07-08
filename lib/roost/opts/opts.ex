defmodule Roost.Opts do
  alias Helen.Module.Config

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
        random_fade_bright: %{
          name: "slow fade",
          activate: true,
          random: %{
            min: 256,
            max: 2048,
            primes: 35,
            step_ms: 55,
            step: 7,
            priority: 7
          }
        },
        random_fade_dim: %{
          name: "slow fade",
          activate: true,
          random: %{
            min: 128,
            max: 1024,
            primes: 35,
            step_ms: 55,
            step: 3,
            priority: 7
          }
        }
      ],
      modes: [
        dance_with_me: [],
        leaving: []
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

  def syntax_version, do: 2

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
