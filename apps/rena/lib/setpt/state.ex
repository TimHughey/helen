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
            transition_min_ms: 60_000,
            last_exec: :none,
            last_notify_at: nil,
            last_transition: DateTime.from_unix!(0),
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
          transition_min_ms: pos_integer(),
          last_exec: last_exec(),
          last_notify_at: nil | DateTime.t(),
          last_transition: DateTime.t(),
          timezone: Timex.time_zone()
        }

  def allow_transition?(%State{last_transition: last, transition_min_ms: ms}, opts \\ []) do
    now = opts[:now] || DateTime.utc_now()

    if DateTime.diff(now, last, :millisecond) > ms, do: true, else: false
  end

  def save_equipment(%State{} = s, %NotifyTo{} = nt), do: %State{s | equipment: nt}

  def transition(%State{} = s), do: %State{s | last_transition: DateTime.utc_now()}

  # (1 of 2) handle pipelining
  def update_last_exec(what, %State{} = s), do: update_last_exec(s, what)

  # (2 of 2) handle pipelining
  def update_last_exec(%State{} = s, what) do
    case what do
      %DateTime{} = at -> %State{s | last_exec: at} |> transition()
      %ExecResult{} = er -> %State{s | last_exec: er}
      :failed -> %State{s | last_exec: :failed}
      _ -> s
    end
  end

  def update_last_notify_at(%State{} = s), do: %State{s | last_notify_at: DateTime.utc_now()}
end
