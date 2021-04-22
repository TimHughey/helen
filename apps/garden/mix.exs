defmodule Garden.MixProject do
  @moduledoc false

  use Mix.Project

  @version "0.9.9"

  def project do
    [
      app: :garden,
      version: @version,
      elixir: "~> 1.11",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      deps: deps(),
      docs: docs(),
      releases: releases(),
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      env: [],
      extra_applications: [:logger],
      mod: {Garden.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:toml, "~> 0.6.1"},
      {:timex, "~> 3.0"},
      {:agnus, "~> 0.1.0"},
      {:helen, in_umbrella: true},
      {:credo, "> 0.0.0", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false}
    ]
  end

  defp docs,
    do: [
      main: "this-is-garden",
      formatter_opts: [gfm: true],
      source_ref: @version,
      source_url: "https://github.com/TimHughey/garden",
      extras: [
        "docs/This Is Garden.md",
        "CHANGELOG.md"
      ]
    ]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp releases do
    [
      garden: [
        version: "0.1.0",
        applications: [garden: :permanent],
        include_erts: true,
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        cookie: "augury-kinship-swain-circus",
        strip_beams: false,
        steps: [
          &sym_link_to_tar_rm/1,
          :assemble,
          :tar,
          &sym_link_to_tar/1
        ]
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
          "garden",
          "_build",
          Atom.to_string(Mix.env())
        ]),
      tarball: "#{release.name}-#{release.version}.tar.gz",
      sym_link: "garden.tar.gz"
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
end
