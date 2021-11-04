defmodule Eva.MixProject do
  use Mix.Project

  def project do
    [
      app: :eva,
      version: "0.3.6",
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

  def application do
    if Mix.env() == :test do
      [
        extra_applications: [:logger],
        mod: {Eva.Application, []}
      ]
    else
      [
        extra_applications: [:logger]
      ]
    end
  end

  defp deps do
    [
      {:alfred, in_umbrella: true},
      {:betty, in_umbrella: true},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:sally, in_umbrella: true},
      {:should, in_umbrella: true, only: :test, runtime: false},
      {:timex, "~> 3.0"},
      {:toml, "~> 0.6.1"}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support", "test/reference_impl"]
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
