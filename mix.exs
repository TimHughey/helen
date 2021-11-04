defmodule Helen.MixProject do
  @moduledoc false

  use Mix.Project

  @vsn "2.0.10"

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
      ]
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    []
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
      garden: :none,
      illumination: :permanent,
      legacy_db: :permanent
    ]
  end
end
