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
      homepage_url: "http://www.wisslanding.com/helen/doc",
      docs: docs()
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  defp deps do
    [
      {:ex_doc, "~> 0.24", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      # The main page in the docs
      main: "readme",
      # logo: "path/to/logo.png",
      extras: ["README.md"],
      groups_for_modules: [
        Alfred: ~r/^Alfred$|Alfred.Status$/,
        "Alfred Immutables": ~r/^Alfred\.[I].*(?<!Aid)$/,
        "Alfred Mutables": ~r/^Alfred\.[EM].*(?<!Aid)$/,
        "Alfred Names": ~r/Alfred\.(Just|Names|Known|Seen).*(?<!Aid)$/,
        "Alfred Notify": ~r/^Alfred\.Notify.*$/,
        "Alfred Test Aids": ~r/^AlfredSim$|^Alfred.*Aid$/,
        "Alfred Testing Mockups": ~r/^Alfred\.Test.*$/,
        Betty: ~r/Betty.*$/,
        Broom: ~r/^Broom.*$/,
        Illumination: ~r/^Illumination.*$|^(Front|Green).*$/,
        "Legacy Database": ~r/^LegacyDb.*$/,
        Rena: ~r/^Rena.*$/,
        Sally: ~r/^Sally$|^Sally\..*(?<!Manual)(?<!Aid)$/,
        "Sally Test Aids": ~r/Sally\.(?:Test.*|.*Aid)$/,
        Should: ~r/^Should.*$/,
        Solar: ~r/^(Solar|Zenith)/,
        Types: ~r/.*Types$/
      ],
      nest_modules_by_prefix: [],
      api_reference: false
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
