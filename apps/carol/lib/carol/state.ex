defmodule Carol.State do
  @moduledoc false

  require Logger

  defstruct server_name: :none,
            # NOTE: name registered with Alfred
            name: :none,
            equipment: :none,
            episodes: [],
            register: nil,
            seen_at: :none,
            status: %{},
            tick: nil,
            ticket: :none,
            ttl_ms: 60_000

  @type t :: %__MODULE__{
          server_name: :none | module(),
          name: String.t(),
          equipment: String.t(),
          episodes: [] | [Carol.Episode.t(), ...],
          register: nil | {:ok, pid},
          seen_at: DateTime.t(),
          status: map,
          tick: nil | reference(),
          ticket: Alfred.Ticket.t(),
          ttl_ms: pos_integer()
        }

  def alfred, do: opts(:alfred) || Alfred

  def freshen_episodes(%{episodes: episodes} = state) do
    sched_opts = sched_opts(state)
    episodes = Carol.Episode.analyze_episodes(episodes, sched_opts)

    struct(state, episodes: episodes)
  end

  @common [:alfred, :id, :opts]
  @want_fields [:name, :instance, :equipment, :episodes]
  @combine [:name, :instance]
  def new(args) do
    {common_opts, args_rest} = Keyword.split(args, @common)
    opts = store_opts(common_opts)

    {fields, args_rest} = Keyword.split(args_rest, @want_fields)
    {defaults, args_extra} = Keyword.pop(args_rest, :defaults, [])

    log_unknown_args(args_extra)

    fields = [server_name: opts[:server_name]] ++ fields

    Enum.map(fields, fn
      # NOTE: defaults are only applicable to episodes
      {:episodes = key, list} -> {key, Carol.Episode.new_from_list(list, defaults)}
      {:equipment = key, val} -> {key, to_name(val)}
      {key, val} when key in @combine -> {:name, to_name(val)}
      kv -> kv
    end)
    |> Enum.dedup()
    |> then(fn fields -> struct(__MODULE__, fields) end)
  end

  def next_tick(%{episodes: episodes} = state) do
    sched_opts = sched_opts(state)

    next_tick_ms = Carol.Episode.ms_until_next(episodes, sched_opts)
    tick = Process.send_after(self(), :tick, next_tick_ms)

    struct(state, tick: tick)
  end

  def opts(keys \\ []) do
    opts = Process.get(:opts)

    case keys do
      key when is_atom(key) -> get_in(opts, [key])
      [_ | _] -> Keyword.take(opts, keys)
      _ -> opts
    end
  end

  def restart(%__MODULE{} = state) do
    _ = Process.send_after(self(), :restart, 0)

    state
  end

  def sched_opts(%{seen_at: seen_at, ttl_ms: ttl_ms}) do
    opts = opts()

    case seen_at do
      %DateTime{} = ref_dt -> ref_dt
      _ -> opts[:timezone] |> Timex.now()
    end
    |> then(fn ref_dt -> [ref_dt: ref_dt, ttl_ms: ttl_ms] ++ opts end)
  end

  def seen_at(state) do
    tz = opts(:timezone)

    struct(state, seen_at: Timex.now(tz))
  end

  @notify_opts [interval_ms: :all]
  def start_notifies(%{ticket: _} = state) do
    alfred = alfred()

    alfred.notify_register(state, @notify_opts)
  end

  def stop_notifies(%{ticket: _} = state) do
    alfred = alfred()

    alfred.notify_unregister(state)
  end

  def store_opts(common_opts) do
    {opts, rest} = Keyword.pop(common_opts, :opts, [])
    {server_name, rest} = Keyword.pop(rest, :id)

    rest
    |> Keyword.put_new(:server_name, server_name)
    |> Keyword.merge(opts)
    |> Keyword.put_new(:alfred, Alfred)
    |> tap(fn opts_all -> Process.put(:opts, opts_all) end)
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  def log_unknown_args(rest) do
    case rest do
      [] ->
        rest

      _ ->
        keys = Keyword.keys(rest)
        log = ["extra args: ", inspect(keys)]

        tap(rest, fn _ -> Logger.warn(log) end)
    end
  end

  def to_name(val) do
    case val do
      <<_::binary>> -> val
      # x when is_atom(x) -> to_string(val) |> String.replace("_", " ")
      x when is_atom(x) -> to_string(val)
    end
  end
end
