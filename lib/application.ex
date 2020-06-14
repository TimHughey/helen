defmodule Helen.Application do
  @moduledoc """
  Helen Application Module
  """
  @moduledoc since: "0.0.3"

  use Application
  require Logger

  @doc """
    Starts Helen Supervisor
  """
  @doc since: "0.0.3"
  @impl true
  def start(:normal, args) do
    import Application, only: [get_env: 3]

    # only start if there are children to supervise and the Repo db passwd
    # exists in the environment
    with {:children, [_ | _] = c} <- {:children, children_list()},
         repo_config <- get_env(:helen, Repo, []),
         db_passwd <- Keyword.get(repo_config, :password),
         {:db_passwd, true} <- {:db_passwd, is_binary(db_passwd)} do
      # we have children to start and the Repo db passwd is set
      log_if_needed(args)

      Supervisor.start_link(c,
        strategy: :rest_for_one,
        name: Helen.Supervisor,
        max_restarts: 100,
        max_seconds: 5
      )
    else
      {:children, []} -> {:error, :no_children}
      {:db_passwd, false} -> {:error, :db_passwd_missing}
      error -> {:error, error}
    end
  end

  def default_opts, do: @type(start_type :: :normal)
  @type args :: term

  ###
  ### PRIVATE
  ###

  defp children_list do
    import Application, only: [get_env: 2]

    make_tuple = fn
      mod, args when is_nil(args) -> {mod, []}
      mod, args -> {mod, Keyword.get(args, :initial_args, [])}
    end

    for mod <- [
          Repo,
          Keeper,
          Fact.Supervisor,
          Mqtt.Supervisor,
          Switch.Supervisor,
          PulseWidth.Supervisor,
          Helen.Scheduler,
          Thermostat.Supervisor,
          ExtraMod.Supervisor,
          ExtraMod
        ] do
      make_tuple.(mod, get_env(:helen, mod))
    end
  end

  defp log_if_needed(args) do
    import Application, only: [get_env: 3]

    log =
      get_env(:helen, Helen.Application, [])
      |> Keyword.get(:log, [])
      |> Keyword.get(:init, true)

    if log,
      do:
        [
          "starting supervisor version=\"",
          Keyword.get(args, :version, "unknown"),
          "\""
        ]
        |> IO.iodata_to_binary()
        |> Logger.info()
  end
end
