defmodule Carol.State do
  @moduledoc false
  alias __MODULE__
  require Logger

  defstruct server_name: :none,
            # NOTE: name registered with Alfred
            name: :none,
            equipment: :none,
            episodes: [],
            register: nil,
            seen_at: :none,
            status: %{},
            ticket: :none,
            ttl_ms: 60_000

  @type t :: %State{
          server_name: :none | module(),
          name: String.t(),
          equipment: String.t(),
          episodes: [] | [Carol.Episode.t(), ...],
          register: nil | {:ok, pid},
          seen_at: DateTime.t(),
          status: map,
          ticket: Alfred.Ticket.t(),
          ttl_ms: pos_integer()
        }

  def alfred, do: Process.get(:opts) |> Keyword.get(:alfred, Alfred)

  def new(args) do
    {opts, rest} = pop_and_put_opts(args)
    {equipment, rest} = pop_equipment(rest)
    {name, rest} = pop_name(rest)
    {defaults, rest} = Keyword.pop(rest, :defaults, [])
    {episodes, rest} = Keyword.pop(rest, :episodes, [])

    log_unknown_args(rest)

    # NOTE: defaults are only applicable to episodes
    episodes = Carol.Episode.new_from_episode_list(episodes, defaults)

    fields = [equipment: equipment, episodes: episodes, server_name: opts[:server_name], name: name]

    struct(__MODULE__, fields)
  end

  def now, do: sched_opts() |> get_in([:ref_dt])

  def opts, do: Process.get(:opts)

  def refresh_episodes(%State{} = s) do
    [episodes: Carol.Episode.analyze_episodes(s.episodes, sched_opts())]
    |> update(s)
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

  def seen_at(s), do: update(s, seen_at: now())

  def start_notifies(%State{ticket: ticket} = state) do
    case ticket do
      x when x in [:none, :pause] ->
        [name: state.equipment, interval_ms: :all]
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

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

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

    case equipment do
      x when is_binary(x) -> equipment
      x when is_atom(x) -> to_string(x) |> String.replace("_", " ")
    end
    |> then(fn equipment -> {equipment, rest} end)
  end

  defp pop_name(args) do
    {instance, rest} = Keyword.pop(args, :instance)

    case instance do
      x when is_atom(x) -> to_string(instance) |> String.replace("_", " ")
      <<_::binary>> -> instance
    end
    |> then(fn name -> {name, rest} end)
  end

  defp update(fields, %__MODULE__{} = s), do: struct(s, fields)
  defp update(%__MODULE__{} = s, fields), do: struct(s, fields)
end
