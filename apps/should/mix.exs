defmodule Should.MixProject do
  use Mix.Project

  def project do
    [
      app: :should,
      version: "0.6.28",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :test,
      deps: deps(),

      ## Compile Paths
      elixirc_paths: elixirc_paths(Mix.env()),

      ## Test Coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: preferred_cli_env(),

      ## Docs
      name: "Should",
      source_url: "https://github.com/timhughey/helen",
      homepage_url: "http://www.wisslanding.com",
      docs: docs()
    ]
  end

  def application, do: []

  defp deps do
    [
      {:excoveralls, "~> 0.10", only: :test},
      {:ex_doc, "~> 0.24", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      # The main page in the docs
      main: "Should",
      # logo: "path/to/logo.png",
      extras: ["README.md"],
      groups_for_modules: [
        "Should Be": [Should.Be, Should.Be.Invalid, Should.Be.Map]
      ]
      # nest_modules_by_prefix: [Should.Be, Be, Should.Contain, Contain]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib"]
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
