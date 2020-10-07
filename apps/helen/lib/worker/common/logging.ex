defmodule Helen.Worker.Common.Logging do
  @moduledoc false

  require Logger

  import Helen.Worker.State.Common

  def log_faults(state) do
    faults = faults_map(state)

    if Enum.empty?(faults) do
      state
    else
      Logger.warn(
        "#{registered_name()} faults #{inspect(faults, pretty: true)}"
      )

      state
    end
  end

  def registered_name(opts \\ [as: :binary]) do
    proc_info = Process.info(self())
    name = proc_info[:registered_name] || :unknown

    if opts[:as] == :binary, do: inspect(name), else: name
  end
end
