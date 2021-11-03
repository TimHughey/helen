defmodule Illumination.State do
  alias __MODULE__

  alias Illumination.Schedule

  defstruct alfred: Alfred,
            module: nil,
            equipment: "unset",
            schedules: [],
            cmds: %{},
            result: nil,
            last_notify_at: nil,
            timezone: "America/New_York"

  @type t :: %State{
          alfred: module(),
          module: module(),
          equipment: String.t() | NotifyTo.t(),
          schedules: list(),
          cmds: map(),
          result: Schedule.Result.t(),
          last_notify_at: DateTime.t(),
          timezone: Timex.time_zone()
        }

  # NOTE: state is passed first for use in pipeline
  def save_equipment(%State{} = s, %Alfred.NotifyTo{} = x),
    do: %State{s | equipment: x}

  # def save_result(%Schedule.Result{} = r, %State{} = s), do: %State{s | result: r}

  def save_schedules_and_result(to_save, %State{} = s) when is_list(to_save) do
    schedules = to_save[:schedules] || s.schedules
    result = to_save[:result] || s.result

    %State{s | schedules: schedules, result: result}
  end

  def update_last_notify_at(%State{} = s) do
    %State{s | last_notify_at: DateTime.utc_now()}
  end
end
