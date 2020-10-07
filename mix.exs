defmodule FatHelen.MixProject do
  @moduledoc false

  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.2",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
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
        version: "0.1.1",
        applications: [helen: :permanent, ui: :permanent],
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
end
