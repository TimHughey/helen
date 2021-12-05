defmodule Carol.Schedule.Result do
  alias __MODULE__
  alias Alfred.ExecCmd

  alias Carol.Schedule
  # alias Carol.Schedule.Point

  defstruct schedule: nil,
            exec: nil,
            queue_timer: nil,
            run_timer: nil,
            action: :none

  @type actions :: :activated | :queued | :live | :finished

  @type t :: %Result{
          schedule: Schedule.t(),
          exec: Alfred.ExecResult.t(),
          queue_timer: reference(),
          run_timer: reference(),
          action: actions()
        }

  # (1 of 2)
  def cancel_timers_if_needed(%Result{} = result) do
    if result.queue_timer, do: Process.cancel_timer(result.queue_timer)
    if result.run_timer, do: Process.cancel_timer(result.run_timer)

    %Result{result | queue_timer: nil, run_timer: nil}
  end

  # (2 of 2)
  def cancel_timers_if_needed(passthrough), do: passthrough

  def expected_cmd(result) do
    case result do
      %Result{action: action} when action in [:live, :activated] -> result.schedule.start.cmd
      _ -> %ExecCmd{cmd: "off"}
    end
  end
end
