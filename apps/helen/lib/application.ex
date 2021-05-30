defmodule Helen.Application do
  @moduledoc """
  Helen Application Module
  """
  @moduledoc since: "0.0.3"

  use Application
  require Logger

  @start_opts [strategy: :rest_for_one, name: Helen.Supervisor, max_restarts: 100, max_seconds: 5]
  @log_init Application.compile_env(:helen, [Helen.Application, :log, :init], false)

  @doc """
    Starts Helen Supervisor
  """
  @doc since: "0.0.3"
  @impl true
  def start(:normal, args) do
    Logger.info(["application starting, working directory: ", "#{inspect(File.cwd(), pretty: true)}"])

    # only start the Repo db passwd is configured

    repo_config = Application.get_env(:helen, Repo, [])

    case repo_config[:password] || :db_passwd_missing do
      db_passwd when is_binary(db_passwd) ->
        mods = mods_to_start()
        log_start(args, mods)
        Supervisor.start_link(mods, @start_opts)

      x ->
        {:error, x}
    end
  end

  # def default_opts, do: @type(start_type :: :normal)
  # @type args :: term

  def children, do: Supervisor.which_children(Helen.Supervisor)

  ###
  ### PRIVATE
  ###

  defp log_start(args, children) do
    if @log_init do
      num_children = (length(children) == 1 && "1 child") || "#{to_string(children)} children"
      vsn = args[:version] || "unknown"

      Logger.info(["starting supervisor, version=", vsn, " with ", num_children])
    end
  end

  defp mods_to_start do
    if only_repo?() do
      [Repo]
    else
      [Repo, Fact.Supervisor, Mqtt.Supervisor, PulseWidth.Execute, Switch.Supervisor, Reef.Supervisor]
    end
  end

  defp only_repo?,
    do: ["/tmp", "helen-repo-only"] |> Path.join() |> File.exists?()
end
