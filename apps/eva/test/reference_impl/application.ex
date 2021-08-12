defmodule Eva.Application do
  @moduledoc false

  use Application

  @habitat_opts Application.compile_env!(:eva, Eva.Habitat)
  @autooff_opts Application.compile_env!(:eva, Eva.RefImpl.AutoOff)
  @ruth_led_opts Application.compile_env!(:eva, Eva.RefImpl.RuthLED)

  @impl true
  def start(_type, _args) do
    children = [
      {Eva.Habitat, @habitat_opts},
      {Eva.RefImpl.AutoOff, @autooff_opts},
      {Eva.RefImpl.RuthLED, @ruth_led_opts}
    ]

    opts = [strategy: :one_for_one, name: Eva.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
