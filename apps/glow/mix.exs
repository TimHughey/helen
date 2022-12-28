defmodule Glow.MixProject do
  use Mix.Project

  def project do
    [
      app: :glow,
      version: "0.4.1",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.12",
      start_permanent: Mix.env() in [:prod, :test],
      deps: deps(),

      ## Compile Paths
      elixirc_paths: elixirc_paths(Mix.env()),

      ## Test Coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: preferred_cli_env(),

      ## Docs
      name: "Glow",
      source_url: "https://github.com/timhughey/helen",
      homepage_url: "http://www.wisslanding.com/helen/doc",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Glow.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:carol, in_umbrella: true},
      #  {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
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
      groups_for_modules: [
        Glow: [~r/^Glow$|^Glow.Instance$/],
        "Glow Instances": [~r/Front|Green/]
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(env) when env in [:dev, :test], do: ["lib"]
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
