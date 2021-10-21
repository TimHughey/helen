defmodule Garden.Application do
  @moduledoc false

  require Logger

  use Application

  alias Garden.{Equipment, Server}

  @cfg_path Application.compile_env!(:garden, :cfg_path)
  @cfg_file Application.compile_env!(:garden, :cfg_file)

  @irrigation [
    # garden: Application.compile_env!(:garden, [Equipment.Irrigation.Garden, :cfg_file]),
    # porch: Application.compile_env!(:garden, [Equipment.Irrigation.Porch, :cfg_file]),
    power: Application.compile_env!(:garden, [Equipment.Irrigation.Power, :cfg_file])
  ]

  @lighting [
    # evergreen: Application.compile_env!(:garden, [Equipment.Lighting.Evergreen, :cfg_file]),
    # red_maple: Application.compile_env!(:garden, [Equipment.Lighting.RedMaple, :cfg_file]),
    # chandelier: Application.compile_env!(:garden, [Equipment.Lighting.Chandelier, :cfg_file]),
    greenhouse: Application.compile_env!(:garden, [Equipment.Lighting.Greenhouse, :cfg_file])
  ]

  def start(_type, _args) do
    children = [
      # {Equipment.Irrigation.Garden, irrigation_opts(:garden)},
      # {Equipment.Irrigation.Porch, irrigation_opts(:porch)},
      {Equipment.Irrigation.Power, irrigation_opts(:power)},
      # {Equipment.Lighting.Evergreen, lighting_opts(:evergreen)},
      # {Equipment.Lighting.RedMaple, lighting_opts(:red_maple)},
      # {Equipment.Lighting.Chandelier, lighting_opts(:chandelier)},
      {Equipment.Lighting.Greenhouse, lighting_opts(:greenhouse)},
      {Server, server_opts()}
    ]

    opts = [strategy: :one_for_one, name: Garden.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp irrigation_opts(which) do
    [cfg_file: Path.join([@cfg_path, @irrigation[which]])]
  end

  defp lighting_opts(which) do
    [cfg_file: Path.join([@cfg_path, @lighting[which]])]
  end

  defp server_opts do
    [cfg_file: Path.join([@cfg_path, @cfg_file])]
  end
end
