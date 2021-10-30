defmodule LegacyDb.MixProject do
  use Mix.Project

  def project do
    [
      app: :legacy_db,
      version: "0.1.6",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {LegacyDb.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:postgrex, ">= 0.0.0"},
      {:ecto_sql, "~> 3.1"},
      {:jason, "~> 1.0"},
      {:timex, "~> 3.0"},
      {:should, in_umbrella: true}
    ]
  end
end
