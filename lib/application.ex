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
        iex> Helen.Application.hot_load("hot-stage", :rm)

        Options:
          directory to load (default: "hot-stage")
          :rm  = delete files after loading (default)
          :no_rm = keep files after loading

  """
  @doc since: "0.0.15"
  def hot_load(dir \\ "hot-stage", delete \\ :rm)
      when is_binary(dir) and is_atom(delete) do
    import File, only: [cwd: 0, ls: 1, rm: 1]
    import Path, only: [join: 1]

    # ignore any redefinitions of modules
    with :ok <- Code.put_compiler_option(:ignore_module_conflict, true),
         {:ok, curr_dir} <- cwd(),
         {:ok, files} <- [curr_dir, dir] |> join() |> ls() do
      for f <- files do
        f_actual = [curr_dir, dir, f] |> join()
        {mod, _bytecode} = Code.compile_file(f_actual) |> hd()
        if delete == :rm, do: _rc = rm(f_actual)

        Code.put_compiler_option(:ignore_module_conflict, true)
        mod
      end
    else
      error ->
        Code.put_compiler_option(:ignore_module_conflict, true)
        error
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

    create_extra_module_dirs(["hot-stage", "extra-mods"])

    # always load the modules in extra-mods before starting the children
    hot_load("extra-mods", :no_rm)

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

  ###
  ### PRIVATE
  ###

  defp create_extra_module_dirs(dirs) do
    {_cwd_rc, curr_dir} = File.cwd()

    for d <- dirs do
      _rc = [curr_dir, d] |> Path.join() |> File.mkdir()
    end
  end
end
