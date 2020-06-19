defmodule Reef.Salt.KeepFresh do
  @moduledoc """
    Implements the aspects of keeping fresh the Salt Water Mix Tank
    before and after mixing
  """

  use Timex

  def abort(opts \\ []) when is_list(opts) do
    alias Reef.Salt.KeepFresh, as: MOD

    for subsystem <- [:air, :pump] do
      task_term_rc = ExtraMod.task_abort({MOD, subsystem})

      with %{pid: pid, task_keys: %{state: %{switch: sw_name}}} <-
             task_term_rc do
        [
          "keep fresh aborting ",
          inspect(subsystem),
          " ",
          inspect(task_term_rc, pretty: true)
        ]
        |> ExtraMod.task_store_msg({MOD, subsystem})

        rc = Switch.off(sw_name, wait_for_pid: pid, timeout_ms: 1500)
        {:aborted, subsystem, sw_name, rc}
      else
        error -> error
      end
    end
  end

  def default_opts do
    [
      switch_air: "mixtank air",
      switch_pump: "mixtank pump",
      keep_fresh_time: [hours: 12],
      air_on: [minutes: 5],
      air_off: [minutes: 15],
      pump_on: [minutes: 2],
      pump_off: [minutes: 60]
    ]
  end

  def kickstart(opts \\ []) when is_list(opts) do
    alias Reef.Salt.KeepFresh, as: MOD

    for sub <- [:air, :pump] do
      with opts <- Keyword.put(opts, :subsystem, sub),
           {:ok, task} <- ExtraMod.task_start({MOD, sub, :run, opts}),
           %{pid: pid} <- task do
        {sub, {:ok, pid}}
      else
        error -> {sub, error}
      end
    end
  end

  @doc """
   Runs the Salt Mix Prep task identified by the key :subsystem in opts
  """

  @doc since: "0.0.23"
  def run(opts \\ []) when is_list(opts) do
    alias Reef.Salt.KeepFresh, as: MOD

    opts_map = Keyword.merge(default_opts(), opts) |> Enum.into(%{})

    start_delay = Map.get(opts_map, :start_delay, nil)

    if is_list(start_delay) do
      delay = TimeSupport.duration(start_delay)
      ms = TimeSupport.duration_ms(delay)

      Process.sleep(ms)
    end

    with %{keep_fresh_duration: _, subsystem: sub} = cm <-
           make_control_map(opts_map) do
      rc = run_subsystem(cm)

      ExtraMod.task_store_rc({MOD, sub, rc})
    else
      error -> error
    end
  end

  @doc """
   Retrieve the latest status message
  """
  @doc since: "0.0.23"
  def status(opts \\ []) do
    alias Reef.Salt.KeepFresh, as: MOD

    for sub <- [:air, :pump] do
      [Atom.to_string(sub), " ", ExtraMod.task_status({MOD, sub}, opts)]
      |> IO.iodata_to_binary()
    end
    |> Enum.join("\n")
    |> IO.puts()
  end

  ##
  ## Private
  ##

  defp run_subsystem(
         %{subsystem: subsystem, start: s, keep_fresh_duration: d} = cm
       ) do
    alias Reef.Salt.KeepFresh, as: MOD

    max_ms = TimeSupport.duration_ms(d)
    elapsed = Duration.elapsed(now(), s)

    # update the cycle count
    %{cycles: cys} = cm = Map.update(cm, :cycles, 1, fn x -> x + 1 end)

    [
      "keep fresh \"",
      Atom.to_string(subsystem),
      "\" starting cycle #",
      Integer.to_string(cys),
      " (elapsed time ",
      TimeSupport.humanize_duration(elapsed),
      ")"
    ]
    |> ExtraMod.task_store_msg({MOD, subsystem})

    case Duration.to_milliseconds(elapsed) do
      # we have yet to pass the requesed runtime, do another cycle
      x when x < max_ms ->
        # turn on, off and sleep the subsystem
        subsystem(cm)

        # call ourselves for another cycle
        run_subsystem(cm)

      _done ->
        # enough time has elapsed, we're done
        Keyword.new() |> Keyword.put(subsystem, :done)
    end
  end

  defp make_control_map(%{subsystem: subsystem} = opts_map) do
    alias Reef.Salt.KeepFresh, as: MOD

    validate = fn
      %{keep_fresh_duration: _, on: _, off: _, switch: _} = x ->
        x

      not_valid ->
        ["invalid control map ", inspect(not_valid, pretty: true)]
        |> ExtraMod.task_store_msg({MOD, subsystem})

        %{}
    end

    # build the base control map with the passed opts and :started
    base = %{start: now()}
    control_map = Map.merge(base, opts_map)

    # convert the :fill and :final opts to durations
    for {key, val} <- control_map, into: %{} do
      cond do
        key == :keep_fresh_time ->
          {:keep_fresh_duration, TimeSupport.duration(val)}

        subsystem == :air and key == :air_on ->
          {:on, TimeSupport.duration(val)}

        subsystem == :air and key == :air_off ->
          {:off, TimeSupport.duration(val)}

        subsystem == :air and key == :switch_air ->
          {:switch, val}

        subsystem == :pump and key == :pump_on ->
          {:on, TimeSupport.duration(val)}

        subsystem == :pump and key == :pump_off ->
          {:off, TimeSupport.duration(val)}

        subsystem == :pump and key == :switch_pump ->
          {:switch, val}

        true ->
          {key, val}
      end
    end
    |> validate.()
  end

  defp now, do: Duration.now()

  defp subsystem(%{switch: sw_name, on: on, off: off}) do
    on_ms = TimeSupport.duration_ms(on)
    off_ms = TimeSupport.duration_ms(off)

    Switch.on(sw_name)
    Process.sleep(on_ms)

    Switch.off(sw_name)
    Process.sleep(off_ms)
  end
end
