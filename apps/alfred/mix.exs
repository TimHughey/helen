defmodule Alfred.MixProject do
  use Mix.Project

  def project do
    [
      app: :alfred,
      version: "0.3.9",
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

      ## Docs
      name: "Alfred",
      source_url: "https://github.com/timhughey/helen",
      homepage_url: "http://www.wisslanding.com/helen/doc",
      docs: [
        # The main page in the docs
        main: "Alfred",
        # logo: "path/to/logo.png",
        extras: ["README.md"],
        groups_for_modules: [
          Execute: [~r/Exec(Cmd|Result)/],
          Names: [~r/(KnownName|JustSaw|Names\.|SeenName)/],
          Immutable: [~r/Immutable/],
          Mutable: [~r/Mutable/],
          Notify: [~r/(Notify.)/],
          "Testing Aids": [~r/Aid/]
        ],
        nest_modules_by_prefix: [Alfred.Immutable, Alfred.Mutable, Alfred.Notify]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Alfred.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:betty, in_umbrella: true},
      {:ecto_sql, "~> 3.1"},
      {:tzdata, "~> 1.1"},
      {:timex, "~> 3.0"},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:ex_doc, "~> 0.24", only: [:dev, :test], runtime: false},
      {:should, in_umbrella: true, only: :test}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(env) when env in [:dev, :test], do: ["lib", "test/shared", "test/impl"]
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
