defmodule Rena.SetPt.State do
  alias __MODULE__

  alias Alfred.{ExecCmd, ExecResult, NotifyTo}
  alias Rena.Sensor

  defstruct alfred: Alfred,
            server_name: nil,
            equipment: "unset",
            sensors: [],
            sensor_range: %Sensor.Range{},
            cmds: nil,
            last_exec: :none,
            last_notify_at: nil,
            timezone: "America/New_York"

  @type cmds :: [{:active, ExecCmd.t()}, {:inactive, ExecCmd.t()}]
  @type last_exec :: :none | :failed | DateTime.t() | ExecCmd.t()
  @type t :: %State{
          alfred: module(),
          server_name: atom(),
          equipment: String.t() | Alfred.NotifyTo.t(),
          sensors: list(),
          sensor_range: Sensor.Range.t(),
          cmds: cmds(),
          last_exec: last_exec(),
          last_notify_at: nil | DateTime.t(),
          timezone: Timex.time_zone()
        }

  def save_equipment(%State{} = s, %NotifyTo{} = nt), do: %State{s | equipment: nt}

  # (1 of 2) handle pipelining
  def update_last_exec(what, %State{} = s), do: update_last_exec(s, what)

  # (2 of 2) handle pipelining
  def update_last_exec(%State{} = s, what) do
    case what do
      %DateTime{} = at -> %State{s | last_exec: at}
      %ExecResult{} = er -> %State{s | last_exec: er}
      :failed -> %State{s | last_exec: :failed}
      _ -> s
    end
  end

  def update_last_notify_at(%State{} = s), do: %State{s | last_notify_at: DateTime.utc_now()}
end
