defmodule RuthSim.MixProject do
  use Mix.Project

  def project do
    [
      app: :ruth_sim,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.11",
      start_permanent: Mix.env() in [:dev, :test],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {RuthSim.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:timex, "~> 3.0"},
      {:tortoise, "~> 0.9"},
      {:msgpax, "~> 2.0"},
      {:ecto_sql, "~> 3.1"}
    ]
  end
end
