defmodule Solar.MixProject do
  use Mix.Project

  def project do
    [
      app: :solar,
      version: "0.1.3",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: preferred_cli_env(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def aliases, do: []

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:timex, "~> 3.0"},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:should, in_umbrella: true, only: :test},
      {:excoveralls, "~> 0.10", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
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
