defmodule Broom.MixProject do
  use Mix.Project

  def project do
    [
      app: :broom,
      version: "0.2.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.11",
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
    if Mix.env() == :test do
      [
        extra_applications: [:logger],
        mod: {Broom.Application, []}
      ]
    else
      [
        extra_applications: [:logger]
      ]
    end
  end

  defp aliases do
    if Mix.env() == :test do
      now = System.os_time(:second) |> to_string()

      backup_file = "#{Mix.env()}-#{now}.sql"
      structure_backup = ["priv", "broom_repo", "structure", backup_file] |> Path.join()

      latest_file = "#{Mix.env()}.sql"
      structure_latest = ["priv", "broom_repo", "structure", latest_file] |> Path.join()

      [
        "broom.ecto.init": [
          "ecto.drop --no-compile",
          "ecto.create --no-compile"
        ],
        "broom.ecto.dump.backup": [
          "ecto.dump --dump-path #{structure_backup}"
        ],
        "broom.ecto.load.latest": [
          "ecto.load --dump-path #{structure_latest}"
        ],
        "broom.ecto.reset": [
          "broom.ecto.dump.backup",
          "broom.ecto.init",
          "broom.ecto.load.latest",
          "ecto.migrate"
        ],
        "ecto.migrate": [
          "ecto.migrate",
          "ecto.dump --dump-path #{structure_latest}"
        ]
      ]
    else
      []
    end
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.1"},
      {:timex, "~> 3.0"},
      {:betty, in_umbrella: true},
      {:should, in_umbrella: true, only: :test, runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:postgrex, ">= 0.0.0", only: :test}
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
