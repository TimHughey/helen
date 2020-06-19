defmodule Reef.Salt.Aerate do
  @moduledoc """
    Implements the aspects of aerating a recently filled Salt Water Mix Tank
    for salt mix
  """

  use Timex

  def abort(opts \\ []) when is_list(opts) do
    alias Reef.Salt.Aerate, as: MOD

    for subsystem <- [:air, :pump] do
      task_term_rc = ExtraMod.task_abort({MOD, subsystem})

      with %{pid: pid, task_keys: %{state: %{switch: sw_name}}} <- task_term_rc do
        [
          "aerate aborting ",
          inspect(subsystem),
          " ",
          inspect(task_term_rc, pretty: true)
        ]
        |> ExtraMod.task_store_msg({MOD, subsystem})

        rc = Switch.off(sw_name, wait_for_pid: pid, timeout_ms: 1500)
        {:aborted, subsystem, sw_name, rc}
      else
        error -> {:aborted, {:error, error}}
      end
    end
  end

  def default_opts do
    [
      switch_air: "mixtank air",
      switch_pump: "mixtank pump",
      aerate_time: [hours: 12],
      air_on: [minutes: 15],
      air_off: [minutes: 5],
      pump_on: [minutes: 5],
      pump_off: [minutes: 30]
    ]
  end

  def elapsed_as_binary(opts \\ []) do
    alias Reef.Salt.Aerate, as: MOD

    cm = ExtraMod.task_get_state({MOD, :air}, opts)

    start = Map.get(cm, :start, Duration.zero())
    end_duration = Map.get(cm, :end, now())

    Duration.elapsed(end_duration, start) |> TimeSupport.humanize_duration()
  end

  def kickstart(opts \\ []) when is_list(opts) do
    alias Reef.Salt.Aerate, as: MOD

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
    alias Reef.Salt.Aerate, as: MOD

    opts_map = Keyword.merge(default_opts(), opts) |> Enum.into(%{})

    with %{aerate_duration: _, subsystem: sub} = cm <-
           make_control_map(opts_map) do
      rc = run_subsystem(cm)

      ExtraMod.task_store_rc({MOD, sub, rc})

      ["aerate ", Atom.to_string(sub), " complete"]
      |> ExtraMod.task_store_msg({MOD, :sub})
    else
      error -> error
    end
  end

  @doc """
   Retrieve the latest status message
  """
  @doc since: "0.0.23"
  def status(opts \\ []) do
    alias Reef.Salt.Aerate, as: MOD

    for sub <- [:air, :pump] do
      [Atom.to_string(sub), " ", ExtraMod.task_status({MOD, sub}, opts)]
      |> IO.iodata_to_binary()
    end
    |> Enum.join("\n")
    |> IO.puts()
  end

  @doc """
   Retrieve the latest state
  """
  @doc since: "0.0.23"
  def state(opts \\ []) do
    alias Reef.Salt.Aerate, as: MOD

    for sub <- [:air, :pump], into: %{} do
      {sub, ExtraMod.task_get_state({MOD, sub}, opts)}
    end
  end

  ##
  ## Private
  ##

  defp elapsed(%{start: start}) do
    Duration.elapsed(now(), start)
  end

  defp elapsed_ms(cm) do
    elapsed(cm) |> TimeSupport.duration_ms()
  end

  defp run_subsystem(%{subsystem: subsystem, start: _, aerate_duration: d} = cm) do
    alias Reef.Salt.Aerate, as: MOD

    max_ms = TimeSupport.duration_ms(d)

    # update the cycle count
    %{cycles: cys} = cm = Map.update(cm, :cycles, 1, fn x -> x + 1 end)

    ExtraMod.task_put_state({MOD, subsystem, cm})

    [
      "aerate \"",
      Atom.to_string(subsystem),
      "\" starting cycle #",
      Integer.to_string(cys),
      " (elapsed time ",
      elapsed(cm) |> TimeSupport.humanize_duration(),
      ")"
    ]
    |> ExtraMod.task_store_msg({MOD, subsystem})

    case elapsed_ms(cm) do
      # we have yet to pass the requesed runtime, do another cycle
      x when x < max_ms ->
        # turn on, off and sleep the subsystem
        subsystem(cm)

        # call ourselves for another cycle
        run_subsystem(cm)

      _done ->
        # enough time has elapsed, fall through
        cm = Map.put(cm, :end, now())
        ExtraMod.task_put_state({MOD, subsystem, cm})
        Keyword.new() |> Keyword.put(subsystem, :done)
    end
  end

  defp make_control_map(%{subsystem: subsystem} = opts_map) do
    alias Reef.Salt.Aerate, as: MOD

    validate = fn
      %{aerate_duration: _, on: _, off: _, switch: _} = x ->
        x

      not_valid ->
        ["invalid control map ", inspect(not_valid, pretty: true)]
        |> ExtraMod.task_store_msg({MOD, subsystem})

        %{}
    end

    # build the base control map with the passed opts and :started
    base = %{start: now()}
    control_map = Map.merge(base, opts_map)

    # convert the :aerate time, :pump and :air keyword lists to Duration
    for {key, val} <- control_map, into: %{} do
      cond do
        key == :aerate_time ->
          {:aerate_duration, TimeSupport.duration(val)}

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

  defp sleep(ms) when is_number(ms) do
    receive do
      {:abort} -> IO.puts("received abort")
      msg -> ["received msg: ", inspect(msg, pretty: true)] |> IO.puts()
    after
      trunc(ms) ->
        :ok
    end
  end

  defp subsystem(%{subsystem: sub, switch: sw_name, on: on, off: off} = cm) do
    on_ms = TimeSupport.duration_ms(on)
    off_ms = TimeSupport.duration_ms(off)

    ExtraMod.task_put_state({MOD, sub, cm})
    Switch.on(sw_name)
    sleep(on_ms)

    ExtraMod.task_put_state({MOD, sub, cm})
    Switch.off(sw_name)
    sleep(off_ms)
  end
end
