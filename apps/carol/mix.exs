defmodule Carol.MixProject do
  use Mix.Project

  def project do
    [
      app: :carol,
      version: "0.2.4",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.12",
      start_permanent: Mix.env() in [:test, :prod],
      deps: deps(),

      ## Compile Paths
      elixirc_paths: elixirc_paths(Mix.env()),

      ## Test Coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: preferred_cli_env(),

      ## Docs
      name: "Carol",
      source_url: "https://github.com/timhughey/helen",
      homepage_url: "http://www.wisslanding.com/helen/doc",
      docs: docs()
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
      {:timex, "~> 3.7"},
      {:solar, in_umbrella: true},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:ex_doc, "~> 0.21", only: [:dev, :test], runtime: false},
      {:should, in_umbrella: true, only: :test}
    ]
  end

  defp docs do
    [
      # The main page in the docs
      main: "readme",
      # logo: "path/to/logo.png",
      extras: ["README.md"],
      nest_modules_by_prefix: [],
      groups_for_modules: []
    ]
  end

  defp elixirc_paths(env) when env in [:dev, :test], do: ["lib", "test/shared"]
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
