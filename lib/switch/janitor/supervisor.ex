defmodule Janitor.Supervisor do
  @moduledoc false

  # require Logger
  # use Supervisor
  #
  # use Config.Helper
  #
  # def init(args) do
  #   log?(:init_args, true) &&
  #     Logger.info(["init() args: ", inspect(args, pretty: true)])
  #
  #   to_start = workers(args)
  #
  #   log?(:init, true) &&
  #     Logger.info(["starting workers ", inspect(to_start, pretty: true)])
  #
  #   to_start
  #   |> Supervisor.init(strategy: :one_for_one, name: __MODULE__)
  # end
  #
  # # supervisors are always autostarted
  # def start_link(args) when is_list(args) do
  #   Supervisor.start_link(__MODULE__, Enum.into(args, %{}), name: __MODULE__)
  # end
  #
  # defp workers(args), do: [{Janitor, args}]
end
