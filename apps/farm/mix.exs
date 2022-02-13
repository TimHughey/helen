defmodule Farm.MixProject do
  use Mix.Project

  def project do
    [
      app: :farm,
      version: "0.3.1",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.12",
      start_permanent: Mix.env() in [:test, :prod],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Farm.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:alfred, in_umbrella: true},
      {:carol, in_umbrella: true},
      {:rena, in_umbrella: true},
      {:should, in_umbrella: true, only: :test}
    ]
  end
end
