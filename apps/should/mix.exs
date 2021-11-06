defmodule Should.MixProject do
  use Mix.Project

  def project do
    [
      app: :should,
      version: "0.6.4",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :test,
      deps: []
    ]
  end

  def application, do: []
end
