defmodule Illumination.MixProject do
  use Mix.Project

  def project do
    [
      app: :illumination,
      version: "0.1.2",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: preferred_cli_env()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Illumination.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:alfred, in_umbrella: true},
      {:broom, in_umbrella: true},
      {:excoveralls, "~> 0.10", only: :test},
      {:timex, "~> 3.7"},
      {:solar, in_umbrella: true},
      {:should, in_umbrella: true, only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/reference_impl"]
  defp elixirc_paths(_), do: ["lib"]

  defp preferred_cli_env do
    [
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end
end
