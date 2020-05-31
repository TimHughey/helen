defmodule Helen.Application do
  @moduledoc """
  Helen Application Module
  """
  @moduledoc since: "0.0.3"

  use Application
  require Logger

  @doc """
      Compile files located in hot-stage


        ### Examples
        iex> Helen.Application.hot_load()

  """
  @doc since: "0.0.15"
  def hot_load do
    import File, only: [cwd: 0, ls: 1, rm: 1]
    import Path, only: [join: 1]

    with {:ok, curr_dir} <- cwd(),
         {:ok, files} <- [curr_dir, "hot-stage"] |> join() |> ls() do
      for f <- files do
        f_actual = [curr_dir, "hot-stage", f] |> join()
        {mod, _bytecode} = Code.compile_file(f_actual) |> hd()
        _rc = rm(f_actual)
        mod
      end
    else
      error -> error
    end
  end

  @doc """
    Starts Helen Supervisor
  """
  @doc since: "0.0.3"
  @impl true
  def start(start_type, args)

  def start(:normal, args) do
    import Application, only: [get_env: 2, get_env: 3]
    import Keyword, only: [has_key?: 2]

    mod_opts = get_env(:helen, Helen.Application, default_opts())

    log =
      Keyword.get(mod_opts, :log, [])
      |> Keyword.get(:init, true)

    {_cwd_rc, curr_dir} = File.cwd()

    # make the hot module compile directory
    _rc = [curr_dir, "hot-stage"] |> Path.join() |> File.mkdir()

    # ["mkdir rc=\"", inspect(rc, pretty: true), "\""] |> Logger.info()

    children =
      for i <- get_env(:helen, :sup_tree, []) do
        if is_tuple(i), do: i, else: get_env(:helen, i)
      end
      |> List.flatten()

    log &&
      Logger.info(["will start: ", inspect(children, pretty: true)])

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [
      strategy: :rest_for_one,
      name: Helen.Supervisor,
      max_restarts: 100,
      max_seconds: 5
    ]

    # only start the Supervisor if the database password is set
    if get_env(:helen, Repo, []) |> has_key?(:password) do
      Logger.info([
        "starting supervisor version[",
        Keyword.get(args, :version, "unknown"),
        "]"
      ])

      Supervisor.start_link(children, opts)
    else
      {:error, :no_db_password}
    end
  end

  def default_opts, do: [log: [init: false]]

  @type start_type :: :normal
  @type args :: term
end
