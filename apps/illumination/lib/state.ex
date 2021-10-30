defmodule Illumination.State do
  alias __MODULE__

  alias Illumination.Schedule

  defstruct alfred: Alfred,
            module: nil,
            equipment: "unset",
            schedules: [],
            cmds: %{},
            result: nil,
            timezone: "America/New_York"

  @type t :: %State{
          alfred: module(),
          module: module(),
          equipment: String.t() | NotifyTo.t(),
          schedules: list(),
          cmds: map(),
          result: Schedule.Result.t(),
          timezone: Timex.time_zone()
        }

  def save_equipment(%Alfred.NotifyTo{} = x, %State{} = s),
    do: %State{s | equipment: x}

  def save_result(%Schedule.Result{} = r, %State{} = s), do: %State{s | result: r}

  def save_schedules_and_result(to_save, %State{} = s) when is_list(to_save) do
    %State{s | schedules: to_save[:schedules], result: to_save[:result]}
  end
end
