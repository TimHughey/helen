defmodule Helen.Application do
  @moduledoc """
  Helen Application Module
  """
  @moduledoc since: "0.0.3"

  use Application
  require Logger
  import Application, only: [get_env: 2, get_env: 3, put_env: 3]
  import Keyword, only: [has_key?: 2]

  @log_opts get_env(:helen, Helen.Application, []) |> Keyword.get(:log, [])

  @doc """
    Starts Helen Supervisor


  """
  @doc since: "0.0.3"
  @impl true
  def start(start_type, args)

  def start(:normal, args) do
    log = Keyword.get(@log_opts, :init, true)

    log &&
      Logger.info(["start() ", inspect(args, pretty: true)])

    build_env = Keyword.get(args, :build_env, "dev")

    put_env(:helen, :build_env, build_env)

    children =
      for i <- get_env(:helen, :sup_tree) do
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
        "build_env[",
        build_env,
        "] version[",
        Keyword.get(args, :version, "unknown"),
        "] starting supervisor "
      ])

      Supervisor.start_link(children, opts)
    else
      {:error, :no_db_password}
    end
  end

  @type start_type :: :normal
  @type args :: term
end
