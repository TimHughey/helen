defmodule Helen.Workers do
  @moduledoc """
  Abstraction to find the module for a Worker.

  A worker is either:
    a. a Reef worker (e.g. FirstMate)
    b. a GenDevice (e.g. Reef.MixTank.Air)
    c. a simple device (e.g. Switch, PulseWidth)
  """

  import Helen.Worker.State
  import Helen.Workers.ModCache, only: [module: 2]

  def add_via_msg(action),
    do: put_in(action, [:via_msg], true) |> put_in([:wait], true)

  def build_module_cache(nil), do: %{}

  def build_module_cache(workers_map) when is_map(workers_map) do
    for {ident, name} <- workers_map, into: %{} do
      {ident, module(ident, name)}
    end
  end

  def module_cache_complete?(cache) do
    for {_ident, entry} <- cache, reduce: true do
      true -> entry[:found?] || false
      false -> false
    end
  end

  def execute(state) do
    action = pending_action(state)
    result = execute_action(action)

    cmd_rc_put(state, result)
  rescue
    anything ->
      IO.puts(inspect(anything, pretty: true))
      IO.puts(inspect(__STACKTRACE__, pretty: true))

      IO.puts(
        inspect(pending_action(state) |> Map.drop([:worker_cache]), pretty: true)
      )

      state
  end

  # NOTE: has test case
  @doc false
  def execute_action(%{stmt: :sleep, args: duration, reply_to: pid} = action) do
    import Helen.Time.Helper, only: [to_ms: 1]

    execute_result(action, fn ->
      Process.send_after(pid, make_msg(action), to_ms(duration))
    end)
  end

  def execute_action(
        %{
          stmt: :tell,
          worker: %{type: worker_type, module: mod},
          worker_cmd: worker_cmd,
          msg: msg
        } = action
      )
      when worker_type in [:temp_server, :reef_worker] do
    action
    |> execute_result(fn -> apply(mod, worker_cmd, [msg]) end)
  end

  # NOTE: has test case
  @doc false
  def execute_action(%{stmt: :all, args: cmd, worker_cache: wc} = action) do
    IO.puts("stmt all, worker_cache: #{inspect(wc, pretty: true)}")

    execute_result(action, fn ->
      for {ident, %{module: mod, found?: true, type: type} = worker}
          when type in [:simple_device, :gen_device] <- wc,
          into: %{} do
        # add the worker to the action for matching by the executing module
        action = worker_cmd_put(action, cmd) |> put_in([:worker], worker)

        IO.puts(
          "all execute_action() action: #{
            inspect(Map.drop(action, [:worker_cache]), pretty: true)
          }"
        )

        {ident, mod.execute_action(action)}
      end
    end)
  end

  def execute_action(%{stmt: :cmd_list, cmd: cmd, worker: workers} = action) do
    execute_result(action, fn ->
      for %{ident: ident, module: mod, found?: true, type: type} = worker
          when type in [:simple_device, :gen_device] <- workers,
          into: %{} do
        # add the worker to the action for matching by the executing module
        action = worker_cmd_put(action, cmd) |> put_in([:worker], worker)

        {ident, mod.execute_action(action)}
      end
    end)
  end

  def execute_action(%{stmt: :cmd_basic, worker: %{module: mod}} = action) do
    execute_result(action, fn -> mod.execute_action(action) end)
  end

  def execute_action(%{stmt: stmt, worker: %{module: mod}} = action)
      when stmt in [:cmd_for, :cmd_for_then] do
    action = add_via_msg(action)

    execute_result(action, fn -> mod.execute_action(action) end)
  end

  def make_action(msg_type, worker_cache, action, %{token: token} = state) do
    Map.merge(action, %{
      msg_type: msg_type,
      worker_cache: worker_cache,
      worker: resolve_worker(worker_cache, action[:worker]),
      reply_to: self(),
      action_ref: make_ref(),
      token: token
    })
    |> make_action_specific(state)
  end

  def make_action_specific(%{cmd: cmd} = action, state) do
    case cmd do
      :all ->
        worker_cmd_put(action, action[:args])

      :tell ->
        worker_cmd_put(action, :mode) |> put_in([:mode], action[:msg])

      :sleep ->
        add_via_msg(action)

      cmd when cmd in [:on, :off, :duty] ->
        worker_cmd_put(action, cmd)

      cmd_def ->
        worker_cmd_put(action, :custom)
        |> put_in([:custom], cmd_definition(state, cmd_def))
    end
  end

  def make_msg(%{msg_type: type} = action),
    do: {type, action}

  def execute_result(%{stmt: _, cmd: _} = action, func),
    do: put_in(action, [:result], func.())

  @doc false
  # resolve the worker ident to the internal module details
  def resolve_worker(cache, worker_ident) do
    case worker_ident do
      nil ->
        nil

      :self ->
        :self

      # deak with the case when the worker is a simple atom
      ident when is_atom(ident) ->
        get_in(cache, [ident])

      # deal with the case when the "worker" is a list of workers
      idents when is_list(idents) ->
        for ident <- idents do
          get_in(cache, [ident])
        end
    end
  end

  def worker_cmd_put(%{for: _} = action, val) do
    put_in(action, [:worker_cmd], val)
    |> put_in([:notify], %{at_start: true, at_finish: true})
  end

  def worker_cmd_put(action, val), do: put_in(action, [:worker_cmd], val)
end
