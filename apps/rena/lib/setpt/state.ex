defmodule Rena.SetPt.State do
  alias __MODULE__

  alias Rena.Sensor

  defstruct alfred: Alfred,
            server_name: nil,
            equipment: "unset",
            ticket: :none,
            sensors: [],
            sensor_range: %Sensor.Range{},
            cmds: %{},
            transition_min_ms: 60_000,
            last_exec: :none,
            last_notify_at: :none,
            last_transition: DateTime.from_unix!(0),
            timezone: "America/New_York"

  @type cmds :: [{:active, list()}, {:inactive, list()}]
  @type last_exec :: :none | :failed | DateTime.t() | Alfred.Execute.t()
  @type ticket() :: :none | :paused | Alfred.Ticket.t()
  @type t :: %State{
          alfred: module(),
          server_name: atom(),
          equipment: String.t() | Alfred.Ticket.t(),
          ticket: ticket(),
          sensors: list(),
          sensor_range: Sensor.Range.t(),
          cmds: cmds(),
          transition_min_ms: pos_integer(),
          last_exec: last_exec(),
          last_notify_at: nil | DateTime.t(),
          last_transition: DateTime.t(),
          timezone: Calendar.time_zone()
        }

  def allow_transition?(%State{last_transition: last, transition_min_ms: ms}, opts \\ []) do
    now = opts[:now] || DateTime.utc_now()

    if DateTime.diff(now, last, :millisecond) > ms, do: true, else: false
  end

  def new(args) do
    struct(State, args) |> finalize_cmds() |> finalize_range()
  end

  def pause_notifies(%State{ticket: ticket} = s) do
    case ticket do
      %Alfred.Ticket{} = x ->
        s.alfred.notify_unregister(x)
        save_ticket(:paused, s)

      x when x in [:none, :paused] ->
        s
    end
  end

  def save_ticket({:ok, ticket}, state), do: struct(state, ticket: ticket)
  def save_ticket(status, state) when is_atom(status), do: struct(state, ticket: status)

  @notify_opts [interval_ms: :all, missing_ms: 60_000]
  def start_notifies(%State{alfred: alfred} = s) do
    [{:name, s.equipment} | @notify_opts] |> alfred.notify_register() |> save_ticket(s)
  end

  def transition(%State{} = s), do: %State{s | last_transition: DateTime.utc_now()}

  # (1 of 2) handle pipelining
  def update_last_exec(what, %State{} = s), do: update_last_exec(s, what)

  # (2 of 2) handle pipelining
  def update_last_exec(%State{} = s, what) do
    case what do
      %DateTime{} = at -> %State{s | last_exec: at} |> transition()
      %Alfred.Execute{} = execute -> struct(s, last_exec: execute) |> transition()
      :failed -> %State{s | last_exec: :failed}
      _ -> s
    end
  end

  def update_last_notify_at(%State{} = s), do: %State{s | last_notify_at: DateTime.utc_now()}

  ##
  ## Private
  ##

  defp finalize_cmds(%State{cmds: cmds} = s) do
    struct(s, cmds: Enum.into(cmds, %{}))
  end

  defp finalize_range(%State{sensor_range: range} = s) do
    struct(s, sensor_range: Sensor.Range.new(range))
  end
end
