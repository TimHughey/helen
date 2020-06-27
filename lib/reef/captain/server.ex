defmodule Reef.Captain.Server do
  @moduledoc """
  Orchestration of Reef Activities (e.g. salt mix, cleaning)
  """

  use GenServer, restart: :transient, shutdown: 7000
  use Helen.Module.Config

  alias Reef.DisplayTank.Ato
  alias Reef.MixTank.{Air, Pump, Rodi}

  ##
  ## GenServer Start and Initialization
  ##

  @doc false
  @impl true
  def init(args) do
    import Helen.Time.Helper, only: [epoch: 0, zero: 0]

    # just in case we were passed a map?!?
    args = Enum.into(args, [])

    state = %{
      mode: args[:mode] || :active,
      reef_mode: :ready,
      standby_reason: :none,
      last_timeout: epoch(),
      timeouts: 0,
      opts: config_opts(args),
      clean: %{
        status: :ready
      },
      fill: %{
        status: :ready,
        steps: [],
        steps_to_execute: [],
        step: %{cmd: :none},
        started_at: nil,
        will_finish_by: nil,
        finished_at: nil,
        elapsed: zero(),
        opts: []
      },
      aerate: %{},
      keep_fresh: %{},
      salt_mix: %{},
      change_prep: %{},
      token: 1
    }

    # should the server start?
    cond do
      state[:mode] == :standby -> :ignore
      true -> {:ok, state, {:continue, :bootstrap}}
    end
  end

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ##
  ## Public API
  ##

  @doc """
  Is the server active?

  Returns a boolean.

  ## Examples

      iex> Reef.Temp.Control.active?
      true

  """
  @doc since: "0.0.27"
  def active? do
    case state([:mode, :reef_mode]) do
      %{active: _, reef_mode: :not_ready} -> false
      %{active: :standby, reef_mode: _} -> false
      _else -> true
    end
  end

  @doc """
  Bring all reef activities to a stop.

  Returns :ok

  ## Examples

      iex> Reef.Captain.Server.all_stop
      :ok

  """
  @doc since: "0.0.27"
  def all_stop, do: GenServer.call(__MODULE__, {:all_stop})

  @doc """
  Enable cleaning mode.

  Display tank ato is stopped for the configured clean duration.

  If unconfigured the default is [hours: 2]

  Returns :ok.

  ## Examples

      iex> Reef.Captain.Server.clean()
      :ok

  """
  @doc since: "0.0.27"
  def clean, do: call_if_active({:clean})

  @doc """
  Fill the MixTank with RODI.

  Returns `:ok`, `{:not_configured, opts}` or `{:invalid_duration_opts}`

  ## Examples

      iex> Reef.Captain.Server.fill()
      :ok

  """
  @doc since: "0.0.27"
  def fill(opts) do
    # opts specified here are automatically placed under the :fill key
    # so they can be succesfully merged with the overall opts
    opts = [opts] |> List.flatten()
    config_opts = config_opts([])

    final_opts = Keyword.merge(config_opts[:fill], opts)
    valid? = validate_durations(final_opts)

    cond do
      valid? == false ->
        {:invalid_duration_opts, final_opts}

      is_nil(final_opts) ->
        {:fill_opts_undefined, final_opts}

      true ->
        cast_if_active({:fill, final_opts})
    end
  end

  @doc """
  Return the status of the Reef fill command.

  Returns a map.

  ## Examples

      iex> Reef.Captain.Server.fill_status()
      :ok

  """
  @doc since: "0.0.27"
  def fill_status, do: call_if_active({:fill_status}) |> IO.puts()

  def last_timeout do
    import Helen.Time.Helper, only: [epoch: 0, utc_now: 0]

    with last <- state(:last_timeout),
         d when d > 0 <- Timex.diff(last, epoch()) do
      Timex.to_datetime(last, "America/New_York")
    else
      _epoch -> epoch()
    end
  end

  @doc """
  Set the mode of the server.

  ## Modes
  When set to `:active` (normal mode) the server will actively control
  the temperature based on the readings of the configured sensor by
  turning on and off the switch.

  If set to `:standby` the server will:
    1. Ensure the switch if off
    2. Continue to receive updates from sensors and switches
    3. Will *not* attempt to control the temperature.

  Returns {:ok, new_mode}

  ## Examples

      iex> Reef.Temp.Control.mode(:standby)
      {:ok, :standby}

  """
  @doc since: "0.0.27"
  def mode(atom) when atom in [:active, :standby] do
    GenServer.call(__MODULE__, {:mode, atom})
  end

  @doc """
  Restarts the server via the Supervisor

  ## Examples

      iex> Reef.Temp.Control.restart([])
      :ok

  """
  @doc since: "0.0.27"
  def restart(opts \\ []) do
    # the Supervisor is the base of the module name with Supervisor appended
    [sup_base | _tail] = Module.split(__MODULE__)

    sup_mod = Module.concat([sup_base, "Supervisor"])

    if GenServer.whereis(__MODULE__) do
      Supervisor.terminate_child(sup_mod, __MODULE__)
    end

    Supervisor.delete_child(sup_mod, __MODULE__)
    Supervisor.start_child(sup_mod, {__MODULE__, opts})
  end

  def state(keys \\ []) do
    if is_nil(GenServer.whereis(__MODULE__)) do
      :DOWN
    else
      keys = [keys] |> List.flatten()

      state = GenServer.call(__MODULE__, :state)

      case keys do
        [] -> state
        [x] -> Map.get(state, x)
        x -> Map.take(state, [x] |> List.flatten())
      end
    end
  end

  def timeouts, do: state() |> Map.get(:timeouts)

  ##
  ## GenServer handle_* callbacks
  ##

  @doc false
  @impl true
  def handle_call(:state, _from, s), do: reply(s, s)

  @doc false
  @impl true
  def handle_call({:all_stop}, _from, %{opts: _opts} = state) do
    for c <- crew_list() do
      apply(c, :mode, [:standby])
    end

    change_token(state)
    |> put_in([:reef_mode], :all_stop)
    |> reply(:answering_all_stop)
  end

  @doc false
  @impl true
  def handle_call({:clean}, _from, %{opts: opts} = state) do
    [{cmd, cmd_opts}] = opts[:clean]

    # NOTE:  if a clean cycle is already in progress the call
    #        to Ato will invalidate it's timer so the previous
    #        clean cycle is effectively canceled
    apply_cmd(cmd, Ato, add_notify_opts(cmd_opts))

    state
    # clear out the previous clean cycle, if any
    |> put_in([:clean], %{})
    |> put_in([:clean, :status], :requested)
    |> put_in([:clean, :opts], opts[:clean])
    |> reply(:ok)
  end

  @doc false
  @impl true
  def handle_call({:fill_status}, _from, %{fill: fill} = state) do
    import Helen.Time.Helper, only: [to_binary: 1]

    {state, msg} =
      case fill[:status] do
        :ready ->
          {state,
           """
           Reef Fill is Ready
           """}

        :completed ->
          {state,
           """
           Reef Fill Completed

             Elapsed time #{to_binary(fill[:elapsed])}.

              Started: #{to_binary(fill[:started_at])}
             Finished: #{to_binary(fill[:finished_at])}
           """}

        :in_progress ->
          state = fill_update_elapsed(state)
          fill = state[:fill]

          {state,
           """
           Reef Fill In-Progress, elapsed time #{to_binary(fill[:elapsed])}.

                   Started: #{to_binary(fill[:started_at])}
           Expected Finish: #{to_binary(fill[:will_finish_by])}

                 Executing: #{inspect(fill[:active_step])}
                 Remaining: #{inspect(fill[:steps_to_execute] |> tl())}
                   Command: #{inspect(fill[:step][:cmd])}
                   Elapsed: #{to_binary(fill[:step][:elapsed])}
                    Cycles: #{inspect(fill[:step][:cycles])}
           """}
      end

    reply(state, msg)
  end

  @doc false
  @impl true
  def handle_cast({:fill, fill_opts}, state) do
    import Helen.Time.Helper, only: [utc_now: 0, utc_shift: 1]

    filtered_steps = fn opts ->
      case get_in(opts, [:steps_to_execute]) do
        nil ->
          {opts[:steps], Keyword.keys(opts[:steps])}

        # steps to execute specified in opts, however filter
        # the list by the steps available
        x ->
          steps = Keyword.take(opts[:steps], x)
          {steps, Keyword.keys(steps)}
      end
    end

    {steps, to_execute} = filtered_steps.(fill_opts)

    fill = %{
      status: :in_progress,
      steps: steps,
      steps_to_execute: to_execute,
      active_step: hd(to_execute),
      step: %{},
      started_at: utc_now(),
      will_finish_ms: will_finish_by_ms(steps),
      will_finish_by: utc_shift(will_finish_by_ms(steps)),
      finished_at: nil,
      elapsed: 0,
      opts: fill_opts
    }

    state
    |> change_token()
    |> put_in([:reef_mode], :fill)
    |> put_in([:fill], fill)
    |> fill_start_active_step()
    |> noreply()
  end

  @doc false
  @impl true
  def handle_cast({:keep_fresh, _opts}, state) do
    noreply(state)
  end

  @doc false
  @impl true
  def handle_cast({:handoff, _cmd} = msg, state) do
    case msg do
      {:handoff, :keep_fresh = cmd} ->
        GenServer.cast(__MODULE__, {cmd, []})
        noreply(state)

      msg ->
        msg_puts(msg, state)
    end
  end

  @doc false
  @impl true
  def handle_continue(:bootstrap, state) do
    valid_opts? = validate_durations(state[:opts])

    case valid_opts? do
      true ->
        noreply(state)

      false ->
        state
        |> put_in([:reef_mode], :not_ready)
        |> put_in([:not_ready_reason], :invalid_opts)
        |> noreply()
    end
  end

  @doc false
  @impl true
  def handle_info({:gen_device, {at_phase, :off, Ato}}, state) do
    import Helen.Time.Helper, only: [utc_now: 0, elapsed: 2]

    case at_phase do
      :at_start ->
        state
        |> put_in([:clean, :started_at], utc_now())
        |> put_in([:clean, :ato_rc], Ato.value())
        |> put_in([:clean, :status], :active)
        |> noreply()

      :at_finish ->
        now = utc_now()
        started_at = state[:clean][:started_at]

        state
        |> put_in([:clean, :finished_at], now)
        |> put_in([:clean, :ato_rc], Ato.value())
        |> put_in([:clean, :status], :complete)
        |> put_in([:clean, :elapsed], elapsed(started_at, now))
        |> noreply()
    end
  end

  @doc false
  @impl true
  # FILL MODE
  def handle_info(
        {:gen_device, {_at_phase, _cmd, Rodi} = msg},
        %{
          reef_mode: :fill,
          fill: %{
            active_step: step,
            steps: steps
          }
        } = state
      ) do
    import Helen.Time.Helper, only: [scale: 2, to_duration: 1, utc_now: 0]

    case msg do
      {:at_start, cmd, Rodi} when cmd in [:on, :off] ->
        # for :at_start we only want to record the executing cmd
        state
        |> put_in([:fill, :step, :cmd], cmd)
        |> noreply()

      {:at_finish, :on, Rodi} ->
        # for :at_finish and :on we want to start off and update :active_cmd
        # to pattern match

        # NOTE:  we do not check the elapsed step time against :run_for
        #        :at_finish, :on.  this purposeful as we never want to
        #        end a step with Rodi on for :fill
        get_in(steps, [step, :off]) |> add_notify_opts() |> Rodi.off()

        air_run_for =
          get_in(steps, [step, :off, :for]) |> to_duration() |> scale(0.25)

        Air.on(for: air_run_for)

        state
        |> put_in([:fill, :cmd], :off)
        |> noreply()

      {:at_finish, :off, Rodi} ->
        # for :at_finish and :off we have finished a cycle of this step
        # NOTE:  we rely on fill_start_active_step to decide if another cycle
        #        of the current step is necessary (based on :run_for) or if the
        #        next step should be executed,
        #
        state
        |> fill_start_active_step()
        |> noreply()
    end
  end

  @doc false
  @impl true
  def handle_info({:gen_device, _} = msg, state), do: msg_puts(msg, state)

  @doc false
  @impl true
  # handle the case when the msg_token matches the current state.
  def handle_info(
        {:timer, _msg, msg_token},
        %{token: token} = s
      )
      when msg_token == token do
    noreply(s)
  end

  # NOTE:  when the msg_token does not match the state token then
  #        a change has occurred and this off message should be ignored
  def handle_info({:timer, _msg, msg_token}, %{token: token} = s)
      when not msg_token == token do
    noreply(s)
  end

  @doc false
  @impl true
  def handle_info(:timeout, state) do
    state
    |> update_last_timeout()
    |> timeout_hook()
  end

  ##
  ## PRIVATE
  ##

  defp add_notify_opts(opts), do: [opts, notify: [:at_start, :at_finish]]

  defp apply_cmd(cmd, mod, opts) do
    case cmd do
      :on -> apply(mod, cmd, [opts])
      :off -> apply(mod, cmd, [opts])
    end
  end

  defp call_if_active(msg) do
    if active?(), do: GenServer.call(__MODULE__, msg), else: {:standby_mode}
  end

  defp cast_if_active(msg) do
    if active?(), do: GenServer.cast(__MODULE__, msg), else: {:standby_mode}
  end

  defp crew_list, do: [Air, Pump, Rodi]

  defp fill_finally(%{fill: %{steps: steps}} = state) do
    import Helen.Time.Helper, only: [elapsed: 2, elapsed?: 2, utc_now: 0]

    # :finally is a "reserved keyword" and requires special handling as it
    # is not a typical fill step but rather an instruction of what to
    # do when all steps complete

    GenServer.cast(__MODULE__, get_in(steps, [:finally, :msg]))

    # :finally is also the last step and, as such, signals the end of
    # the fill command.  record finished_at and calculate the
    # elapsed duration and note fill is completed.
    now = utc_now()
    started_at = get_in(state, [:fill, :started_at])

    # NOTE: we return the updated step, with fill containing only relevant keys
    state
    |> update_in([:fill], fn x -> Map.take(x, [:started_at]) end)
    |> put_in([:fill, :finished_at], now)
    |> put_in([:fill, :elapsed], elapsed(started_at, now))
    |> put_in([:fill, :status], :completed)
  end

  defp fill_start_active_step(%{fill: %{active_step: a, steps: s}} = state)
       when a == :finally or s == [],
       do: fill_finally(state)

  defp fill_start_active_step(state), do: fill_start_next_step_if_needed(state)

  defp fill_start_next_step_if_needed(
         %{fill: %{active_step: active_step, steps: steps}} = state
       ) do
    import Helen.Time.Helper,
      only: [subtract_list: 1, elapsed: 2, elapsed?: 2, utc_now: 0]

    # each step contains a :run_for key that defines how long the
    # step will will cycle on and off
    started_at = get_in(state, [:fill, :step, :started_at]) || utc_now()

    # to prevent exceeding the configured run_for include the duration of the
    # step about to start in the elapsed?
    config_run_for = get_in(steps, [active_step, :run_for])
    on_for = get_in(steps, [active_step, :on, :for])
    off_for = get_in(steps, [active_step, :off, :for])

    # NOTE:  this design decision may result in the fill running for less
    #        time then the run_for configuration when the duration of the steps
    #        do not fit evenly
    run_for = subtract_list([config_run_for, on_for, off_for])

    case elapsed?(started_at, run_for) do
      false ->
        # run_for has not elapsed so turn on Rodi.
        # NOTE:  we always turn on Rodi when starting a step even if :on is not
        #        listed first.  this is a design decision and design constraint
        Air.off()
        get_in(steps, [active_step, :on]) |> add_notify_opts() |> Rodi.on()

        state
        |> put_in([:fill, :step, :started_at], started_at)
        |> put_in([:fill, :step, :elapsed], elapsed(started_at, utc_now()))
        |> update_in([:fill, :step, :cycles], fn
          nil -> 1
          x -> x + 1
        end)

      true ->
        import List, only: [delete_at: 2]

        # run_for has elapsed, remove the current active step from
        # steps_to_execute, clear out the step tracked (:step) then call
        # this function again to start the next step
        state
        # set the active step to the next one in the list of steps to execute
        |> put_in(
          [:fill, :active_step],
          get_in(state, [:fill, :steps_to_execute]) |> hd()
        )
        # remove the step just completed
        |> update_in([:fill, :steps_to_execute], fn x -> delete_at(x, 0) end)
        # a new step is about to begin, reset the step control map
        |> put_in([:fill, :step], %{cmd: :none})
        # call fill_start_active_step
        |> fill_start_active_step()
    end
  end

  defp fill_update_elapsed(
         %{fill: %{started_at: started, step: %{started_at: step_started}}} =
           state
       ) do
    import Helen.Time.Helper, only: [elapsed: 2, utc_now: 0]

    state
    |> put_in([:fill, :elapsed], elapsed(started, utc_now()))
    |> put_in([:fill, :step, :elapsed], elapsed(step_started, utc_now()))
  end

  defp msg_puts(msg, state) do
    """
     ==> #{inspect(msg)}

    """
    |> IO.puts()

    noreply(state)
  end

  # primary entry point for validating durations
  defp validate_durations(opts) do
    # validate the opts with an initial accumulator of true so an empty
    # list is considered valid
    validate_duration_r(opts, true)
  end

  defp validate_duration_r(opts, acc) do
    import Helen.Time.Helper, only: [valid_ms?: 1]

    case {opts, acc} do
      # end of a list (or all list), simply return the acc
      {[], acc} ->
        acc

      # seen a bad duration, we're done
      {_, false} ->
        false

      {[{_k, list} | _rest], acc} when is_list(list) ->
        validate_duration_r(list, acc)

      # look at the head of the list, when it's key of interest
      # validate it can be converted to milliseconds and recurse
      # the tail
      {[{k, v} | rest], acc} when k in [:run_for, :for] ->
        validate_duration_r(rest, acc and valid_ms?(v))

      # not a keyword of interest, keep going
      {{_k, _v}, acc} ->
        acc
    end
  end

  defp will_finish_by_ms(steps) do
    import Helen.Time.Helper, only: [to_ms: 1]

    # unfold each step in the  steps list matching on the key :run_for.
    # convert each value to ms and reduce with a start value of 0.
    for {_step, details} <- steps,
        {k, run_for} when k == :run_for <- details,
        reduce: 0 do
      total_ms -> total_ms + to_ms(run_for)
    end
  end

  ##
  ## GenServer Receive Loop Hooks
  ##

  defp timeout_hook(%{} = s) do
    noreply(s)
  end

  ##
  ## State Helpers
  ##

  defp change_token(%{} = s), do: update_in(s, [:token], fn x -> x + 1 end)

  defp loop_timeout(%{opts: opts}) do
    import Helen.Time.Helper, only: [to_ms: 2]

    to_ms(opts[:timeout], "PT30.0S")
  end

  # defp state_merge(%{} = s, %{} = map), do: Map.merge(s, map)

  defp update_last_timeout(s) do
    import Helen.Time.Helper, only: [utc_now: 0]

    put_in(s, [:last_timeout], utc_now())
    |> Map.update(:timeouts, 1, &(&1 + 1))
  end

  ##
  ## handle_* return helpers
  ##

  defp noreply(s), do: {:noreply, s, loop_timeout(s)}

  # defp noreply_and_merge(s, map), do: {:noreply, Map.merge(s, map)}

  defp reply(s, val) when is_map(s), do: {:reply, val, s, loop_timeout(s)}
  defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}
end
