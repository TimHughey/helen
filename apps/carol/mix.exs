defmodule Carol.MixProject do
  use Mix.Project

  def project do
    [
      app: :carol,
      version: "0.2.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.12",
      start_permanent: Mix.env() in [:test, :prod],
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: preferred_cli_env()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:alfred, in_umbrella: true},
      {:betty, in_umbrella: true},
      {:broom, in_umbrella: true},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:timex, "~> 3.7"},
      {:solar, in_umbrella: true},
      {:should, in_umbrella: true, only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/shared"]
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