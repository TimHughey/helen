defmodule Sally.MixProject do
  use Mix.Project

  def project do
    [
      app: :sally,
      version: "0.5.2",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.12",
      start_permanent: Mix.env() in [:prod, :test],
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
      extra_applications: [:logger],
      mod: {Sally.Application, []}
    ]
  end

  defp aliases do
    if Mix.env() == :test do
      now = System.os_time(:second) |> to_string()

      backup_file = "#{Mix.env()}-#{now}.sql"
      structure_backup = ["priv", "sally_repo", "structure", backup_file] |> Path.join()

      latest_file = "#{Mix.env()}.sql"
      structure_latest = ["priv", "sally_repo", "structure", latest_file] |> Path.join()

      [
        "sally.ecto.init": [
          "ecto.drop --no-compile",
          "ecto.create --no-compile"
        ],
        "sally.ecto.dump.backup": [
          "ecto.dump --dump-path #{structure_backup}"
        ],
        "sally.ecto.load.latest": [
          "ecto.load --dump-path #{structure_latest}"
        ],
        "sally.ecto.reset": [
          "sally.ecto.dump.backup",
          "sally.ecto.init",
          "sally.ecto.load.latest",
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
      {:msgpax, "~> 2.0"},
      {:postgrex, ">= 0.0.0", only: :test},
      {:tortoise, "~> 0.9"},
      {:toml, "~> 0.6.1"},
      {:alfred, in_umbrella: true},
      {:betty, in_umbrella: true},
      {:broom, in_umbrella: true},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:should, in_umbrella: true, only: :test, runtime: false},
      {:excoveralls, "~> 0.10", only: :test}
    ]
  end

  # Specifies which paths to compile per environment.
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
