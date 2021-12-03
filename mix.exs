defmodule Helen.MixProject do
  @moduledoc false

  use Mix.Project

  @vsn "2.1.11"

  def project do
    [
      apps_path: "apps",
      version: @vsn,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],

      ## Docs
      name: "Helen",
      source_url: "https://github.com/timhughey/helen",
      homepage_url: "http://www.wisslanding.com",
      docs: [
        # The main page in the docs
        main: "readme",
        # logo: "path/to/logo.png",
        extras: ["README.md"],
        groups_for_modules: [],
        nest_modules_by_prefix: []
      ]
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      {:ex_doc, "~> 0.24", only: [:dev, :test], runtime: false}
    ]
  end

  defp releases do
    [
      helen: [
        version: @vsn,
        applications: applications(),
        include_erts: true,
        include_executables_for: [:unix],
        cookie: "augury-kinship-swain-circus",
        strip_beams: false,
        steps: [:assemble, :tar]
      ]
    ]
  end

  defp applications do
    [
      runtime_tools: :permanent,
      alfred: :permanent,
      betty: :permanent,
      broom: :permanent,
      sally: :permanent,
      illumination: :permanent,
      legacy_db: :permanent,
      farm: :permanent
    ]
  end
end
