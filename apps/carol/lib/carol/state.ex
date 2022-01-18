defmodule Carol.State do
  @moduledoc false
  alias __MODULE__
  require Logger

  defstruct server_name: :none,
            equipment: :none,
            episodes: [],
            cmd_live: :none,
            ticket: :none,
            exec_result: :none,
            notify_at: :none

  @type t :: %State{
          server_name: :none | module(),
          equipment: String.t(),
          episodes: [] | [Carol.Episode.t(), ...],
          cmd_live: :none | String.t(),
          ticket: Alfred.Ticket.t(),
          exec_result: Alfred.Execute.t(),
          notify_at: DateTime.t()
        }

  def alfred, do: Process.get(:opts) |> Keyword.get(:alfred, Alfred)

  def new(args) do
    {opts, rest} = pop_and_put_opts(args)
    {equipment, rest} = pop_equipment(rest)
    {defaults, rest} = Keyword.pop(rest, :defaults, [])
    {episodes, rest} = Keyword.pop(rest, :episodes, [])
    {wrap?, rest} = Keyword.pop(rest, :wrap_ok, false)

    log_unknown_args(rest)

    # NOTE: defaults are only applicable to episodes
    episodes = Carol.Episode.new_from_episode_list(episodes, defaults)

    [equipment: equipment, episodes: episodes, server_name: opts[:server_name]]
    |> then(fn fields -> struct(State, fields) end)
    |> wrap_ok_if_requested(wrap?)
  end

  def refresh_episodes(%State{} = s) do
    [episodes: Carol.Episode.analyze_episodes(s.episodes, sched_opts())]
    |> update(s)
  end

  def save_cmd(cmd, %State{} = state) do
    case cmd do
      %Alfred.Execute{} = execute -> [cmd_live: Alfred.execute_to_binary(execute)]
      anything -> [cmd_live: anything]
    end
    |> update(state)
  end

  def save_exec_result(%Alfred.Execute{} = execute, %State{} = s) do
    state = update([exec_result: execute], s)

    save_cmd(execute, state)
  end

  def save_ticket(ticket_rc, %State{} = s) do
    case ticket_rc do
      x when is_atom(x) -> x
      {:ok, x} -> x
      x -> {:failed, x}
    end
    |> then(fn ticket -> struct(s, ticket: ticket) end)
  end

  def sched_opts do
    opts = Process.get(:opts)
    tz = opts[:timezone]

    [List.to_tuple([:ref_dt, Timex.now(tz)]) | opts] |> Enum.sort()
  end

  def start_notifies(%State{ticket: ticket} = state) do
    case ticket do
      x when x in [:none, :pause] ->
        [name: state.equipment, frequency: :all, link: true]
        |> alfred().notify_register()
        |> save_ticket(state)

      x when is_struct(x) ->
        state
    end
  end

  def stop_notifies(%State{ticket: ticket} = state) do
    case ticket do
      x when is_struct(x) ->
        alfred().notify_unregister(ticket)
        :pause

      x when is_atom(x) ->
        x
    end
    |> save_ticket(state)
  end

  def timeout(%State{} = s), do: Carol.Episode.ms_until_next_episode(s.episodes, sched_opts())

  def update_notify_at(s) do
    tz = Keyword.get(sched_opts(), :timezone)

    struct(s, notify_at: Timex.now(tz))
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  def atom_to_equipment(instance) do
    base = to_string(instance) |> String.replace("_", " ")

    [base, "pwm"] |> Enum.join(" ")
  end

  defp log_unknown_args([]), do: []

  defp log_unknown_args(rest) do
    ["extra args: ", Keyword.keys(rest) |> inspect()]
    |> Logger.warn()

    rest
  end

  defp pop_and_put_opts(args) do
    {opts, rest} = Keyword.pop(args, :opts, [])
    {alfred, rest} = Keyword.pop(rest, :alfred, Alfred)
    {server_name, rest} = Keyword.pop(rest, :id)

    # ensure Alfred is set
    opts_all = Keyword.put_new(opts, :alfred, alfred) ++ [server_name: server_name]

    Process.put(:opts, opts_all)

    # return tuple of opts first element, rest second element
    {opts_all, rest}
  end

  defp pop_equipment(args) do
    {equipment, rest} = Keyword.pop(args, :equipment)
    {instance, rest} = Keyword.pop(rest, :instance)

    case equipment do
      x when is_binary(x) -> equipment
      x when is_atom(x) -> atom_to_equipment(instance)
    end
    |> then(fn equipment -> {equipment, rest} end)
  end

  defp update(fields, %State{} = s) when is_list(fields) or is_map(fields), do: struct(s, fields)

  defp wrap_ok_if_requested(%State{} = state, wrap?) do
    (wrap? && {:ok, state}) || state
  end
end
