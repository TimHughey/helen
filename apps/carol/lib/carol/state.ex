defmodule Carol.State do
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
          ticket: Alfred.Notify.Ticket.t(),
          exec_result: %Alfred.ExecResult{},
          notify_at: DateTime.t()
        }

  @doc false
  # def add_equipment_to_opts({execute, defaults}, %State{equipment: equipment}) do
  #   {[List.to_tuple([:equipment, equipment]) | execute], defaults}
  # end
  #
  # def add_equipment_to_opts(opts, %State{equipment: equipment}) when is_list(opts) do
  #   [List.to_tuple([:equipment, equipment]) | opts]
  # end

  @doc false
  def alfred, do: Process.get(:opts) |> Keyword.get(:alfred)

  @doc since: "0.3.0"
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

  @doc false
  def refresh_episodes(%State{} = s) do
    [episodes: Carol.Episode.analyze_episodes(s.episodes, sched_opts())]
    |> update(s)
  end

  @doc false
  def save_cmd(cmd, %State{} = s), do: [cmd_live: cmd] |> update(s)

  # @doc false
  # def save_episodes(episodes, %State{} = s), do: update([episodes: episodes], s)

  @doc false
  def save_exec_result(%Alfred.ExecResult{} = er, %State{} = s) do
    [exec_result: er, cmd_live: er.cmd] |> update(s)
  end

  @doc false
  def save_ticket(ticket_rc, %State{} = s) do
    case ticket_rc do
      x when is_atom(x) -> x
      {:ok, x} -> x
      x -> {:failed, x}
    end
    |> then(fn ticket -> struct(s, ticket: ticket) end)
  end

  @doc since: "0.3.0"
  def sched_opts do
    opts = Process.get(:opts)
    tz = opts[:timezone]

    [List.to_tuple([:ref_dt, Timex.now(tz)]) | opts]
  end

  @doc since: "0.3.0"
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

  @doc since: "0.3.0"
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

  @doc since: "0.3.0"
  def timeout(%State{} = s), do: Carol.Episode.ms_until_next_episode(s.episodes, sched_opts())

  @doc since: "0.3.0"
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

    [[alfred: alfred, server_name: server_name] | opts]
    |> List.flatten()
    |> tap(fn opts_all -> Process.put(:opts, opts_all) end)
    |> then(fn opts_all -> {opts_all, rest} end)
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
