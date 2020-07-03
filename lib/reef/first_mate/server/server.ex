defmodule Reef.FirstMate.Server do
  @moduledoc """
  Provides support to Reef.FirstMate.Server, specificially reef clean mode.
  """

  use GenServer, restart: :transient, shutdown: 7000
  use Helen.Module.Config

  alias Reef.DisplayTank.Ato

  ##
  ## GenServer Start and Initialization
  ##

  @doc false
  @impl true
  def init(args) do
    # just in case we were passed a map?!?
    args = Enum.into(args, [])

    create_default_config_if_needed()

    state = %{
      server_mode: args[:server_mode] || :active,
      server_standby_reason: :none,
      token: nil,
      token_at: nil,
      reef_mode: :ready,
      timeouts: %{last: :never, count: 0},
      opts: config_opts(args),
      delayed_cmd: %{}
    }

    # should the server start?
    cond do
      state[:server_mode] == :standby -> :ignore
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

      iex> Reef.FirstMate.Server.active?
      true

  """
  @doc since: "0.0.27"
  def active? do
    case x_state() do
      %{server_mode: :standby, reef_mode: _} -> false
      %{server_mode: _, reef_mode: :not_ready} -> false
      _else -> true
    end
  end

  @doc """
  Bring all reef activities to a stop.

  Returns :ok

  ## Examples

      iex> Reef.FirstMate.Server.all_stop
      :ok

  """
  @doc since: "0.0.27"
  def all_stop, do: GenServer.call(__MODULE__, {:all_stop})

  @doc """
  Enable cleaning mode.

  Display tank ato is stopped for the configured clean duration.

  Required parameters:
    `mode:` <mode defined in config>
    `opts:` [] | <list to merge into config opts>

  Returns :ok.

  ## Examples

      iex> Reef.FirstMate.Server.mode(:clean, [])
      :ok

  """
  @doc since: "0.0.27"
  def mode(mode, opts), do: cast_if_valid_and_active(mode, opts)

  @doc """
  Return the DateTime of the last GenServer timeout.
  """
  @doc since: "0.0.27"
  def last_timeout do
    import Helen.Time.Helper, only: [epoch: 0, utc_now: 0]

    with last <- x_state(:last_timeout),
         d when d > 0 <- Timex.diff(last, epoch()) do
      Timex.to_datetime(last, "America/New_York")
    else
      _epoch -> epoch()
    end
  end

  @doc """
  Set the mode of the server.

  ## Modes
  When set to `:active` (normal mode) the server is ready for reef commands.

  If set to `:standby` the server will:
    1. Switch on the DisplayTank auto-top-off
    2. Denies all reef command mode requeests

  Returns {:ok, new_mode}

  ## Examples

      iex> Reef.FirstMate.Server(:standby)
      {:ok, :standby}

  """
  @doc since: "0.0.27"
  def server_mode(atom) when atom in [:active, :standby] do
    GenServer.call(__MODULE__, {:server_mode, atom})
  end

  @doc """
  Restarts the server via the Supervisor

  ## Examples

      iex> Reef.FirstMate.Server.restart([])
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

  @doc """
  Return the GenServer state.

  A single key (e.g. :server_mode) or a list of keys (e.g. :reef_mode, :server_mode)
  can be specified and only those keys are returned.
  """
  @doc since: "0.0.27"
  def x_state(keys \\ []) do
    import Helen.Time.Helper, only: [utc_now: 0]

    if is_nil(GenServer.whereis(__MODULE__)) do
      :DOWN
    else
      keys = [keys] |> List.flatten()

      state =
        GenServer.call(__MODULE__, :state)
        |> Map.drop([:opts])
        |> put_in([:state_at], utc_now())

      case keys do
        [] -> state
        [x] -> Map.get(state, x)
        x -> Map.take(state, [x] |> List.flatten())
      end
    end
  end

  @doc """
  Retrieve the number of GenServer timeouts that have occurred.
  """
  @doc since: "0.0.27"
  def timeouts, do: x_state() |> Map.get(:timeouts)

  ##
  ## GenServer handle_* callbacks
  ##

  @doc false
  @impl true
  def handle_call(:state, _from, state) do
    state = update_elapsed(state)
    reply(state, state)
  end

  @doc false
  @impl true
  def handle_call({:all_stop}, _from, state) do
    state
    |> all_stop__()
    |> reply(:answering_all_stop)
  end

  @doc false
  @impl true
  def handle_call({:server_mode, mode}, _from, state) do
    case mode do
      # when switching to :standby ensure the switch is off
      :standby ->
        state
        |> change_token()
        |> crew_offline()
        |> put_in([:server_mode], mode)
        |> put_in([:server_standby_reason], :api)
        |> reply({:ok, mode})

      # no action when switching to :active, the server will take control
      :active ->
        state
        |> change_token()
        |> crew_online()
        |> put_in([:server_mode], mode)
        |> put_in([:server_standby_reason], :none)
        |> reply({:ok, mode})
    end
  end

  @doc false
  @impl true
  def handle_cast({:delayed_cmd, cmd, cmd_opts}, state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    # grab the requested delay and remove :start_delay from the opts
    {[{_, delay}], opts} = Keyword.split(cmd_opts, [:start_delay])

    msg = {:delayed_cmd, cmd, opts}

    state
    |> put_in([:delayed_cmd, :cmd], {cmd, cmd_opts})
    |> put_in([:delayed_cmd, :issued_at], utc_now())
    |> change_token_and_send_after(msg, delay)
    |> noreply()
  end

  @doc false
  @impl true
  # START A CASTED MODE
  def handle_cast({mode, cmd_opts}, %{opts: opts} = state) do
    import DeepMerge, only: [deep_merge: 2]

    cmd_opts = deep_merge(opts[mode], cmd_opts)

    state
    |> ensure_reef_mode_map(mode)
    |> put_in([mode, :status], :in_progress)
    |> put_in([mode, :steps], cmd_opts[:steps])
    |> put_in([mode, :sub_steps], cmd_opts[:sub_steps])
    |> put_in([mode, :step_devices], cmd_opts[:step_devices])
    |> put_in([mode, :opts], cmd_opts)
    |> start_mode(mode)
    |> noreply()
  end

  @doc false
  @impl true
  def handle_continue(:bootstrap, state) do
    valid_opts? = validate_durations(state[:opts])

    case valid_opts? do
      true ->
        state
        |> change_token()
        |> crew_online()
        |> set_all_modes_ready()
        |> noreply()

      false ->
        state
        |> put_in([:reef_mode], :not_ready)
        |> put_in([:not_ready_reason], :invalid_opts)
        |> noreply()
    end
  end

  @doc false
  @impl true
  def handle_info(
        {:gen_device, %{token: msg_token, mod: mod, at: at, cmd: cmd}},
        %{
          reef_mode: reef_mode,
          token: token
        } = state
      )
      when msg_token == token do
    import Helen.Time.Helper, only: [utc_now: 0]

    # for all messages we want capture when they were received and update
    # the elapsed time
    state =
      put_in(state, [reef_mode, :device_last_cmds, mod, cmd, at], utc_now())
      |> update_elapsed()

    # we only want to process :at_finish messages from step_devices
    # associated to steps and not sub steps
    active_step = get_in(state, [reef_mode, :active_step])

    expected_mod =
      get_in(state, [reef_mode, :step_devices, active_step])
      |> step_device_to_mod()

    if expected_mod == mod and at == :at_finish,
      do: state |> start_next_cmd_in_step() |> noreply(),
      else: state |> noreply()
  end

  @doc false
  @impl true
  # quietly drop gen_device messages that do not match the current token
  def handle_info(
        {:gen_device, %{token: msg_token}},
        %{token: token} = state
      )
      when msg_token != token,
      do: noreply(state)

  @doc false
  @impl true
  def handle_info({:gen_device, _payload} = msg, state) do
    msg_puts(msg, state)
  end

  @doc false
  @impl true
  # handle the case when the msg_token matches the current state.
  def handle_info({:timer, msg, msg_token}, %{token: token} = state)
      when msg_token == token do
    case msg do
      {:delayed_cmd, :clean, opts} ->
        GenServer.cast(__MODULE__, {:clean, opts})

        state
        |> put_in([:delayed_cmd], %{})
        |> noreply()

      _msg ->
        noreply(state)
    end
  end

  # NOTE:  when the msg_token does not match the state token then
  #        a change has occurred and this off message should be ignored
  def handle_info({:timer, msg, msg_token}, %{token: token} = state)
      when msg_token != token do
    case msg do
      {:delayed_cmd, _cmd} ->
        # if this was a delayed cmd message that failed the token match
        # then null out the delayed_cmd map
        state
        |> put_in([:delayed_cmd], %{})
        |> noreply()

      _no_match ->
        noreply(state)
    end
  end

  @doc false
  @impl true
  def handle_info(:timeout, state) do
    state
    |> update_last_timeout()
    |> timeout_hook()
  end

  @doc false
  @impl true
  def terminate(_reason, %{reef_mode: reef_mode} = state) do
    case reef_mode do
      # :keep_fresh -> state |> all_stop__()
      _nomatch -> state
    end
  end

  ##
  ## PRIVATE
  ##

  defp add_notify_opts_include_token(%{token: t}, opts),
    do: [opts, notify: [:at_start, :at_finish, token: t]] |> List.flatten()

  defp apply_cmd(state, dev, cmd, opts)
       when dev in [:air, :pump, :rodi, :ato] and cmd in [:on, :off] do
    cmd_opts = add_notify_opts_include_token(state, opts)

    apply(step_device_to_mod(dev), cmd, [cmd_opts])
  end

  # skip unmatched commands, devices
  defp apply_cmd(_state, _dev, _cmd, _opts), do: {:no_match}

  defp all_stop__(state) do
    state
    # prevent processing of any lingering messages
    |> change_token()
    # the safest way to stop everything is to take all the crew offline
    |> crew_offline()
    # bring them back online so they're ready for whatever comes next
    |> crew_online()
    |> set_all_modes_ready()
  end

  defp assemble_reef_mode_final_opts(reef_mode, overrides) do
    import DeepMerge, only: [deep_merge: 2]

    opts = [overrides] |> List.flatten()
    config_opts = config_opts([])

    deep_merge(get_in(config_opts, [reef_mode]), opts)
  end

  defp step_device_to_mod(dev) do
    case dev do
      :ato -> Ato
    end
  end

  defp change_reef_mode(%{reef_mode: old_reef_mode} = state, new_reef_mode) do
    update_running_mode_status = fn
      # x, :keep_fresh ->
      #   import Helen.Time.Helper, only: [utc_now: 0]
      #
      #   put_in(x, [:keep_fresh, :status], :completed)
      #   |> put_in([:keep_fresh, :finished_at], utc_now())

      x, _anything ->
        x
    end

    update_running_mode_status.(state, old_reef_mode)
    |> put_in([:reef_mode], new_reef_mode)
    |> change_token()
  end

  defp config_device_to_mod(atom) when atom in [:ato] do
    case atom do
      :ato -> Ato
    end
  end

  defp crew_list, do: [Ato]
  defp crew_list_no_heat, do: [Ato]

  # NOTE:  state is unchanged however is parameter for use in pipelines
  defp crew_offline(state) do
    for crew_member <- crew_list() do
      apply(crew_member, :mode, [:standby])
    end

    state
  end

  # NOTE:  state is unchanged however is parameter for use in pipelines
  defp crew_online(state) do
    # NOTE:  we NEVER bring MixTank.Temp online unless explictly requested
    #        in a mode step/cmd
    for crew_member <- crew_list_no_heat() do
      apply(crew_member, :mode, [:active])
    end

    state
  end

  def ensure_reef_mode_map(state, mode), do: state |> Map.put_new(mode, %{})

  defp msg_puts(msg, state) do
    """
     ==> #{inspect(msg)}

    """
    |> IO.puts()

    noreply(state)
  end

  defp ensure_sub_steps_off(%{reef_mode: reef_mode} = state) do
    sub_steps = get_in(state, [reef_mode, :sub_steps]) || []

    for {step, _cmds} <- sub_steps do
      dev = get_in(state, [reef_mode, :step_devices, step])
      apply_cmd(state, dev, :off, at_cmd_finish: :off)
    end

    state
  end

  defp finish_mode(%{reef_mode: mode} = state) do
    import Helen.Time.Helper, only: [elapsed: 2, utc_now: 0]

    # record the mode execution metrics
    started_at = get_in(state, [mode, :started_at])
    now = utc_now()

    state
    |> ensure_sub_steps_off()
    |> put_in([mode, :status], :completed)
    |> put_in([mode, :finished_at], now)
    |> put_in([mode, :elapsed], elapsed(started_at, now))
    |> put_in([:reef_mode], :ready)
    |> change_token()
  end

  ##
  ## ENTRY POINT FOR STARTING A REEF MODE
  ##  ** only called once per reef mode change
  ##
  defp start_mode(state, reef_mode) do
    import Helen.Time.Helper, only: [utc_now: 0]

    # local function to build the device last cmds map for each device
    device_last_cmds =
      for {_k, v} <- get_in(state, [reef_mode, :step_devices]) || [],
          into: %{} do
        map = %{
          off: %{at_finish: nil, at_start: nil},
          on: %{at_finish: nil, at_start: nil}
        }

        {config_device_to_mod(v), map}
      end

    steps = get_in(state, [reef_mode, :steps])

    change_reef_mode(state, reef_mode)
    |> calculate_will_finish_by_if_needed()
    # mode -> :device_last_cmds is 'global' for the mode and not specific
    # to a single step or command
    |> put_in([reef_mode, :steps_to_execute], Keyword.keys(steps))
    |> put_in([reef_mode, :started_at], utc_now())
    |> put_in([reef_mode, :device_last_cmds], device_last_cmds)
    |> put_in([reef_mode, :step], %{})
    |> put_in([reef_mode, :cycles], %{})
    |> start_mode_next_step()
  end

  defp start_mode_next_step(%{reef_mode: reef_mode} = state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    # the next step is always the head of :steps_to_execute
    steps_to_execute = get_in(state, [reef_mode, :steps_to_execute])
    # NOTE:  each clause returns the state, even if unchanged
    cond do
      steps_to_execute == [] ->
        # we've reached the end of this mode!
        state
        |> finish_mode()

      true ->
        next_step = steps_to_execute |> hd()

        cmds = get_in(state, [reef_mode, :steps, next_step])

        state
        # remove the step we're starting
        |> update_in([reef_mode, :steps_to_execute], fn x -> tl(x) end)
        |> put_in([reef_mode, :active_step], next_step)
        # the reef_mode step key contains the control map for the step executing
        |> put_in([reef_mode, :step, :started_at], utc_now())
        |> put_in([reef_mode, :step, :elapsed], 0)
        |> put_in([reef_mode, :step, :run_for], nil)
        |> put_in([reef_mode, :step, :repeat?], nil)
        |> put_in([reef_mode, :step, :cmds_to_execute], cmds)
        |> update_step_cycles()
        |> start_next_cmd_in_step()
    end
  end

  defp start_next_cmd_in_step(%{reef_mode: mode} = state) do
    import Helen.Time.Helper, only: [elapsed?: 2, subtract_list: 1, utc_now: 0]

    active_step = get_in(state, [mode, :active_step])
    cmds_to_execute = get_in(state, [mode, :step, :cmds_to_execute])

    repeat? = get_in(state, [mode, :step, :repeat?]) || false
    run_for = get_in(state, [mode, :step, :run_for])

    # NOTE:  each clause returns the state, even if unchanged
    cond do
      cmds_to_execute == [] and repeat? == true ->
        # when repeating populate the steps to execute with this step
        # at the head of the list and call start_mode_next_step
        steps_to_execute =
          [active_step, get_in(state, [mode, :steps_to_execute])]
          |> List.flatten()

        state
        |> put_in([mode, :steps_to_execute], steps_to_execute)
        |> start_mode_next_step()

      cmds_to_execute == [] ->
        # we've reached the end of this step, start the next one
        state
        |> start_mode_next_step()

      is_binary(run_for) ->
        started_at = get_in(state, [mode, :step, :started_at]) || utc_now()

        # to prevent exceeding the configured run_for include the duration of the
        # step about to start in the elapsed?
        steps = get_in(state, [mode, :steps])
        on_for = get_in(steps, [active_step, :on, :for])
        off_for = get_in(steps, [active_step, :off, :for])

        # NOTE:  this design decision may result in the fill running for less
        #        time then the run_for configuration when the duration of the steps
        #        do not fit evenly
        calculated_run_for = subtract_list([run_for, on_for, off_for])

        if elapsed?(started_at, calculated_run_for) do
          # run_for has elapsed, move on to the next step
          state |> start_mode_next_step()
        else
          # there is still time in this step, run the command
          state |> start_next_cmd_and_pop()
        end

      true ->
        state |> start_next_cmd_and_pop()
    end
  end

  defp start_next_cmd_and_pop(%{reef_mode: mode} = state) do
    next_cmd = get_in(state, [mode, :step, :cmds_to_execute]) |> hd()

    put_in(state, [mode, :step, :next_cmd], next_cmd)
    |> update_in([mode, :step, :cmds_to_execute], fn x -> tl(x) end)
    |> start_next_cmd()
  end

  defp start_next_cmd(%{reef_mode: mode} = state) do
    # example:  state -> keep_fresh -> aerate

    active_step = get_in(state, [mode, :active_step])
    next_cmd = get_in(state, [mode, :step, :next_cmd])

    case next_cmd do
      {:run_for, duration} ->
        # consume the run_for command by putting it in the step control map
        # then call start_next_cmd/1
        state
        |> put_in([mode, :step, :run_for], duration)
        |> start_next_cmd_in_step()

      {:repeat, true} ->
        # consume the repeat command by putting it in the step control map
        # then call start_next_cmd/1
        state
        |> put_in([mode, :step, :repeat?], true)
        |> start_next_cmd_in_step()

      {:msg, _} = msg ->
        GenServer.cast(__MODULE__, msg)
        # if this is the last cmd in the last step (e.g. finally) then the
        # call to start_mode_start_next/1 will wrap up this reef mode
        state |> start_mode_next_step()

      # this is an actual command to start
      {cmd, cmd_opts} when is_list(cmd_opts) and cmd in [:on, :off] ->
        dev = get_in(state, [mode, :step_devices, active_step])

        apply_cmd(state, dev, cmd, cmd_opts)

        state |> put_in([mode, :step, :cmd], cmd)

      # this is a reference to another step cmd
      # execute the referenced step/cmd
      {step_ref, cmd} when is_atom(cmd) ->
        # steps to execute and call ourself again
        dev = get_in(state, [mode, :step_devices, step_ref])
        cmd_opts = get_in(state, [mode, :sub_steps, step_ref, cmd])

        # only attempt to process the sub step if we located the
        # device and opts.  if we couldn't then the step doesn't make
        # sense and is quietly skipped
        if is_atom(dev) and is_list(cmd_opts),
          do: apply_cmd(state, dev, cmd, cmd_opts)

        state |> start_next_cmd_in_step()
    end
  end

  defp update_elapsed(%{reef_mode: mode} = state) do
    import Helen.Time.Helper, only: [elapsed: 2, utc_now: 0]

    if get_in(state, [mode, :status]) do
      now = utc_now()
      started_at = get_in(state, [mode, :started_at])
      step_started_at = get_in(state, [mode, :step, :started_at])

      state
      |> put_in([mode, :elapsed], elapsed(started_at, now))
      |> put_in([mode, :step, :elapsed], elapsed(step_started_at, now))
    else
      state
    end
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

      # process the head (tuple) and the tail (a list or a tuple)
      {[head | tail], acc} ->
        acc && validate_duration_r(head, acc) &&
          validate_duration_r(tail, acc)

      # keep unfolding
      {{_, v}, acc} when is_list(v) ->
        acc && validate_duration_r(v, acc)

      # we have a tuple to check
      {{k, d}, acc} when k in [:run_for, :for] and is_binary(d) ->
        acc && valid_ms?(d)

      # not a tuple of interest, keep going
      {_no_interest, acc} ->
        acc
    end
  end

  defp calculate_will_finish_by_if_needed(%{reef_mode: reef_mode} = state) do
    import Helen.Time.Helper, only: [to_ms: 1, utc_shift: 1]

    # grab the list of steps to avoid redundant traversals
    steps = get_in(state, [reef_mode, :steps])

    # will_finish_by can not be calculated if the reef mode
    # contains the cmd repeat: true
    has_repeat? =
      for {_name, cmds} <- steps, {:repeat, true} <- cmds, reduce: false do
        _acc -> true
      end

    if has_repeat? == true do
      state
    else
      # unfold each step in the steps list matching on the key :run_for.
      # convert each value to ms and reduce with a start value of 0.
      will_finish_by =
        for {_step, details} <- get_in(state, [reef_mode, :steps]),
            {k, run_for} when k == :run_for <- details,
            reduce: 0 do
          total_ms -> total_ms + to_ms(run_for)
        end
        |> utc_shift()

      state |> put_in([reef_mode, :will_finish_by], will_finish_by)
    end
  end

  ##
  ## Configuration Helpers
  ##

  defp create_default_config_if_needed do
    if config_available?() do
      nil
    else
      opts = [
        timeout: "PT1M",
        clean: [
          step_devices: [ato_disable: :ato, ato_enable: :ato],
          steps: [
            ato_disable: [
              run_for: "PT1H10S",
              off: [for: "PT1M", at_cmd_finish: :off]
            ],
            ato_enable: [
              run_for: "PT11S",
              on: [for: "PT10S", at_cmd_finish: :on]
            ]
          ]
        ],
        water_change_start: [
          step_devices: [ato_disable: :ato, ato_enable: :ato],
          steps: [
            ato_disable: [
              run_for: "PT3H10S",
              off: [for: "PT1M", at_cmd_finish: :off]
            ],
            ato_enable: [
              run_for: "PT11S",
              on: [for: "PT10S", at_cmd_finish: :on]
            ]
          ]
        ],
        water_change_finish: [
          step_devices: [ato_disable: :ato, ato_enable: :ato],
          steps: [
            ato_disable: [
              run_for: "PT30M10S",
              off: [for: "PT30M", at_cmd_finish: :off]
            ],
            ato_enable: [
              run_for: "PT11S",
              on: [for: "PT10S", at_cmd_finish: :on]
            ]
          ]
        ],
        normal_operations: [
          steps: [
            ato_enable: [
              run_for: "PT11S",
              on: [for: "PT10S", at_cmd_finish: :on]
            ]
          ]
        ]
      ]

      config_create(opts, "auto created defaults")
    end
  end

  def test_opts do
    opts = [
      timeout: "PT1M",
      clean: [
        step_devices: [ato_disable: :ato, ato_enable: :ato],
        steps: [
          ato_disable: [
            run_for: "PT11S",
            off: [for: "PT1S", at_cmd_finish: :off]
          ],
          ato_enable: [
            run_for: "PT3S",
            on: [for: "PT1S", at_cmd_finish: :on]
          ]
        ]
      ],
      water_change_start: [
        step_devices: [ato_disable: :ato, ato_enable: :ato],
        steps: [
          ato_disable: [
            run_for: "PT11S",
            off: [for: "PT1S", at_cmd_finish: :off]
          ],
          ato_enable: [
            run_for: "PT3S",
            on: [for: "PT1S", at_cmd_finish: :on]
          ]
        ]
      ],
      water_change_finish: [
        step_devices: [ato_disable: :ato, ato_enable: :ato],
        steps: [
          ato_disable: [
            run_for: "PT10S",
            off: [for: "PT1S", at_cmd_finish: :off]
          ],
          ato_enable: [
            run_for: "PT11S",
            on: [for: "PT3S", at_cmd_finish: :on]
          ]
        ]
      ],
      normal_operations: [
        steps: [
          ato_enable: [
            run_for: "PT11S",
            on: [for: "PT10S", at_cmd_finish: :on]
          ]
        ]
      ]
    ]

    config_create(opts, "test opts")

    restart()
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

  defp change_token(state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> update_in([:token], fn _x -> make_ref() end)
    |> update_in([:token_at], fn _x -> utc_now() end)
  end

  defp change_token_and_send_after(state, msg, delay) do
    import Helen.Time.Helper, only: [to_ms: 1]

    %{token: token} = state = change_token(state)

    Process.send_after(self(), {:timer, msg, token}, to_ms(delay))

    state
  end

  defp loop_timeout(%{opts: opts}) do
    import Helen.Time.Helper, only: [to_ms: 2]

    to_ms(opts[:timeout], "PT30.0S")
  end

  defp set_all_modes_ready(state) do
    modes = [
      :clean
    ]

    for m <- modes, reduce: state do
      state -> state |> put_in([m], %{status: :ready})
    end
    |> put_in([:reef_mode], :ready)
  end

  defp update_step_cycles(%{reef_mode: mode} = state) do
    active_step = get_in(state, [mode, :active_step])

    update_in(state, [mode, :cycles, active_step], fn
      nil -> 1
      x -> x + 1
    end)
  end

  defp update_last_timeout(state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    state
    |> put_in([:timeouts, :last], utc_now())
    |> update_in([:timeouts, :count], fn x -> x + 1 end)
  end

  ##
  ## GenServer.{call, cast} Helpers
  ##

  # defp call_if_active(msg) do
  #   if active?(), do: GenServer.call(__MODULE__, msg), else: {:standby_mode}
  # end

  defp cast_if_valid_and_active(reef_mode, opts) do
    final_opts = assemble_reef_mode_final_opts(reef_mode, opts)

    valid? = validate_durations(final_opts)
    start_delay = opts[:start_delay]
    skip_active_check? = opts[:skip_active_check] || false
    reef_mode_exists? = get_in(final_opts, [:steps]) || false

    cond do
      valid? == false ->
        {reef_mode, :invalid_duration_opts, final_opts}

      is_nil(final_opts) ->
        {reef_mode, :opts_undefined, final_opts}

      reef_mode_exists? == false ->
        {reef_mode, :does_not_exist}

      is_binary(start_delay) ->
        if active?(),
          do: GenServer.cast(__MODULE__, {:delayed_cmd, reef_mode, final_opts})

      skip_active_check? ->
        GenServer.cast(__MODULE__, {reef_mode, final_opts})

      true ->
        if active?(),
          do: GenServer.cast(__MODULE__, {reef_mode, final_opts}),
          else: {:standby_mode}
    end
  end

  ##
  ## handle_* return helpers
  ##

  defp noreply(s), do: {:noreply, s, loop_timeout(s)}

  defp reply(s, val) when is_map(s), do: {:reply, val, s, loop_timeout(s)}
  defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}
end
