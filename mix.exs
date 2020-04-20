defmodule Helen.Mixfile do
  # Helen Copyright (C) 2020  Tim Hughey (thughey)

  @moduledoc """
    Mix file defining Helen
  """

  use Mix.Project

  def project do
    [
      app: :helen,
      version: "0.0.4",
      elixir: "~> 1.10",
      deps: deps(),
      releases: releases(),
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:gettext] ++ Mix.compilers(),
      aliases: aliases(),
      package: package(),
      description: "Helen",
      escript: escript_config(),
      test_coverage: test_coverage(),
      deploy_paths: deploy_paths(),
      stage_paths: stage_paths(),
      homepage_url: "https://www.wisslanding.com",
      source_url: "https://github.com/TimHughey/helen",
      docs: [
        main: "api-reference.html#modules",
        extras: ["CHANGELOG.md"],
        groups_for_modules: [
          Devices: [PulseWidth, Remote, Sensor, Switch],
          Servers: [Dutycycle, Thermostat]
        ],
        nest_modules_by_prefix: [
          Dutycycle,
          Fact,
          Helen,
          Mqtt,
          PulseWidth,
          Switch,
          Thermostat,
          Remote
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod:
        {Helen.Application,
         [
           version: "#{project() |> Keyword.get(:version)}",
           build_env: "#{Mix.env()}",
           git_vsn: "#{git_describe()}"
         ]},
      extra_applications: [
        :logger,
        :runtime_tools,
        :parse_trans,
        :httpoison
      ]
    ]
  end

  def deploy_paths,
    do: [
      dev: "/tmp/helen/dev",
      test: "/tmp/helen/test",
      prod: "/usr/local/helen"
    ]

  def stage_paths,
    do: [prod: "/tmp"]

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/common"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:timex, "~> 3.0"},
      {:jason, "~> 1.0"},
      {:instream, "~> 0.17"},
      {:hackney, "~> 1.1"},
      {:poolboy, "~> 1.5"},
      {:httpoison, "~> 1.6"},
      {:postgrex, ">= 0.0.0"},
      {:ecto_sql, "~> 3.1"},
      {:tortoise, "~> 0.9"},
      {:uuid, "~> 1.1"},
      {:gettext, "~> 0.11"},
      {:quantum, "~> 2.2"},
      {:scribe, "~> 0.10"},
      {:msgpax, "~> 2.0"},
      {:credo, "> 0.0.0", only: [:dev, :test], runtime: false},
      {:coverex, "~> 1.0", only: :test},
      {:deep_merge, "~> 1.0"},
      {:crontab, "~> 1.1"},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false}
      # {:phoenix, "~> 1.4.0"},
      # {:phoenix_pubsub, "~> 1.0"},
      # {:phoenix_ecto, "~> 4.0"},
      # {:phoenix_html, "~> 2.10"},
      # {:phoenix_live_reload, "~> 1.2", only: :dev},
      # {:plug_cowboy, "~> 2.0"},
      # {:plug, "~> 1.7"},
      # {:guardian, "~> 1.0"},
      # {:ueberauth, "~> 0.4"},
      # {:ueberauth_github, "~> 0.4"},
      # {:ueberauth_identity, "~> 0.2"},
    ]
  end

  defp aliases do
    [
      "ecto.migrate": [
        "ecto.migrate",
        "ecto.dump --dump-path priv/repo/structure-#{Mix.env()}.sql"
      ],
      "ecto.setup": [
        "ecto.create",
        "ecto.load --dump-path priv/repo/structure-prod.sql",
        "ecto.migrate"
      ],
      "ecto.reset": [
        "ecto.drop",
        "ecto.create",
        "ecto.load --dump-path priv/repo/structure-prod.sql",
        "ecto.migrate",
        "ecto.dump --dump-path priv/repo/structure-#{Mix.env()}.sql"
      ],
      "helen.deps.update": [
        "local.hex --if-missing --force",
        "deps.get",
        "deps.clean --unused"
      ]
      # test: ["ecto.create --quiet", "ecto.load", "ecto.migrate", "test"]
    ]
  end

  # defp aliases do
  #   [
  #     "ecto.seed": ["seed"],
  #     "ecto.setup": ["ecto.create", "ecto.migrate --log-sql", "ecto.seed"],
  #     "ecto.reset": ["ecto.drop", "ecto.setup"]
  #   ]
  # end

  defp package do
    [
      name: "helen",
      files: ~w(config extra lib priv rel special test
            .credo.exs .formatter.exs mix.exs
            COPYING* README* LICENSE* CHANGELOG*),
      links: %{"GitHub" => "https://github.com/TimHughey/helen"},
      maintainers: ["Tim Hughey"],
      licenses: ["LGPL-3.0-or-later"]
    ]
  end

  defp escript_config, do: [main_module: Helenp]

  defp git_describe do
    {result, _rc} = System.cmd("git", ["describe"])
    String.trim(result)
  end

  defp test_coverage do
    [
      tool: Coverex.Task,
      ignore_modules: [
        Helen.IExHelpers,
        Fact.Celsius.Fields,
        Fact.Celsius.Tags,
        Fact.EngineMetric.Fields,
        Fact.EngineMetric.Tags,
        Fact.Fahrenheit.Fields,
        Fact.Fahrenheit.Tags,
        Fact.DevMetric.Fields,
        Fact.DevMetric.Tags,
        Fact.FreeRamStat.Fields,
        Fact.FreeRamStat.Tags,
        Fact.LedFlashes.Fields,
        Fact.LedFlashes.Tags,
        Fact.RelativeHumidity.Fields,
        Fact.RelativeHumidity.Tags,
        Fact.RunMetric.Fields,
        Fact.RunMetric.Tags,
        Fact.StartupAnnouncement.Fields,
        Fact.StartupAnnouncement.Tags,
        Repo
      ]
    ]
  end

  defp sym_link_data(release) do
    {:ok, home} = System.fetch_env("HOME")

    %{
      build_path:
        Path.join([
          home,
          "devel",
          "helen",
          "_build",
          Atom.to_string(Mix.env())
        ]),
      tarball: "#{release.name}-#{release.version}.tar.gz",
      sym_link: "helen.tar.gz"
    }
  end

  defp sym_link_to_tar_rm(release) do
    link = sym_link_data(release)

    System.cmd("rm", ["-f", link.tarball],
      cd: link.build_path,
      stderr_to_stdout: true
    )

    release
  end

  defp sym_link_to_tar(release) do
    link = sym_link_data(release)

    System.cmd("ln", ["-sf", link.tarball, link.sym_link],
      cd: link.build_path,
      stderr_to_stdout: true
    )

    release
  end

  defp releases do
    [
      helen: [
        include_erts: true,
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        cookie: "augury-kinship-swain-circus",
        steps: [&sym_link_to_tar_rm/1, :assemble, :tar, &sym_link_to_tar/1]
      ]
    ]
  end
end
