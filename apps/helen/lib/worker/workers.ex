defmodule Helen.Workers do
  @moduledoc """
  Abstraction to find the module for a Worker.

  A worker is either:
    a. a Reef worker (e.g. FirstMate)
    b. a GenDevice (e.g. Reef.MixTank.Air)
  """

  require Logger

  import Helen.Worker.State
  import Helen.Workers.ModCache, only: [module: 2]

  def action_meta_update_elapsed(state) do
    import Helen.Time.Helper, only: [elapsed: 2, utc_now: 0, zero: 0]

    now = utc_now()

    meta = pending_action_meta(state)
    started_at = meta_started_at(state)

    if Enum.empty?(meta) or is_nil(started_at) do
      state
    else
      meta =
        update_in(meta, [:elapsed], fn
          nil -> zero()
          _x -> elapsed(started_at, now)
        end)

      pending_action_meta_put(state, meta)
    end
  end

  def action_run_for(action) do
    import Helen.Time.Helper, only: [zero: 0]

    get_in(action, [:for]) || zero()
  end

  def add_via_msg(action),
    do: put_in(action, [:via_msg], true) |> put_in([:wait], true)

  def add_via_msg_if_needed(action) do
    case action do
      %{for: _} -> add_via_msg(action)
      action -> action
    end
  end

  def build_module_cache(nil), do: %{}

  def build_module_cache(workers) do
    for {ident, name} <- workers, into: %{} do
      {ident, module(ident, name)}
    end
  end

  def execute(state) do
    action = pending_action(state)
    result = execute_action(action)

    cmd_rc_put(state, result)
  rescue
    anything ->
      Logger.warn("rescued: #{inspect(anything, pretty: true)}")
      Logger.warn("#{inspect(__STACKTRACE__, pretty: true)}")
      # Logger.warn("""
      # rescued: #{inspect(anything, pretty: true)}
      #
      # #{inspect(__STACKTRACE__, pretty: true)}
      #
      # #{
      #   inspect(pending_action(state) |> Map.drop([:worker_cache]), pretty: true)
      # }
      # """)

      state
  end

  # NOTE: has test case
  @doc false
  def execute_action(%{cmd: :sleep, for: duration, reply_to: pid} = action) do
    import Helen.Time.Helper, only: [to_ms: 1]

    action
    |> add_via_msg()
    |> execute_result(fn ->
      Process.send_after(pid, make_msg(action), to_ms(duration))
    end)
  end

  def execute_action(
        %{
          cmd: :tell,
          worker: %{type: worker_type, module: mod},
          worker_cmd: worker_cmd,
          msg: msg
        } = action
      )
      when worker_type in [:temp_server, :reef_worker] do
    execute_result(action, fn -> apply(mod, worker_cmd, [msg]) end)
  end

  @doc false
  def execute_action(%{cmd: cmd, worker: workers} = action)
      when is_list(workers) and cmd in [:on, :off] do
    action
    |> execute_result(fn ->
      for {ident, %{module: mod, found?: true, type: type} = worker}
          when type in [:simple_device, :gen_device] <- workers,
          into: %{} do
        # add the worker to the action for matching by the executing module
        action = worker_cmd_put(action, cmd) |> put_in([:worker], worker)

        {ident, mod.execute_action(action)}
      end
    end)
  end

  def execute_action(%{worker: %{module: mod}} = action) do
    execute_result(action, fn -> mod.execute_action(action) end)
  end

  def execute_result(%{cmd: _} = action, func),
    do: put_in(action, [:result], func.())

  def make_action(msg_type, worker_cache, action, %{token: token} = state) do
    import Helen.Time.Helper, only: [utc_now: 0, zero: 0]

    Map.merge(action, %{
      msg_type: msg_type,
      worker: resolve_worker(worker_cache, action[:worker_name]),
      meta: %{
        started_at: utc_now(),
        elapsed: zero(),
        run_for: action_run_for(action)
      },
      reply_to: self(),
      # default to instant processing of the action (e.g. immeidately call
      # next_action/1).  the default can be overriden by calling add_via_msg/1.
      via_msg: false,
      wait: false,
      action_ref: make_ref(),
      token: token
    })
    |> add_via_msg_if_needed()
    |> make_action_specific(state)
  end

  def make_action_specific(%{cmd: cmd} = action, state) do
    case cmd do
      :tell ->
        worker_cmd_put(action, :mode) |> put_in([:msg], action[:mode])

      cmd when cmd in [:on, :off, :duty] ->
        worker_cmd_put(action, cmd)

      cmd ->
        worker_cmd_put(action, :custom)
        |> put_in([:custom], cmd_definition(state, cmd))
    end
  end

  def meta_elapsed(state), do: pending_action_meta(state) |> get_in([:elapsed])

  def meta_started_at(state),
    do: pending_action_meta(state) |> get_in([:started_at])

  def make_msg(%{msg_type: type} = action),
    do: {type, action}

  def module_cache_complete?(cache) do
    for {_ident, entry} <- cache, reduce: true do
      true -> entry[:found?] || false
      false -> false
    end
  end

  @doc false
  # resolve the worker ident to the internal module details
  def resolve_worker(cache, worker_ident) do
    case worker_ident do
      nil ->
        nil

      :self ->
        :self

      :all ->
        cache |> Enum.into([])

      # deak with the case when the worker is a simple atom
      ident when is_atom(ident) ->
        get_in(cache, [ident])

      # deal with the case when the "worker" is a list of workers
      idents when is_list(idents) ->
        Map.take(cache, idents) |> Enum.into([])
    end
  end

  def worker_cmd_put(%{for: _} = action, val) do
    put_in(action, [:worker_cmd], val)
    |> put_in([:notify], %{at_start: true, at_finish: true})
  end

  def worker_cmd_put(action, val), do: put_in(action, [:worker_cmd], val)
end
