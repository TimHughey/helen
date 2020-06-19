defmodule Reef.Salt.Fill do
  @moduledoc """
    Implements the aspects of filling the Salt Water Mix tank with RODI
  """

  use Timex

  def abort(opts \\ []) when is_list(opts) do
    alias Reef.Salt.Fill, as: MOD

    opts_map = Map.merge(Enum.into(opts, %{}), Enum.into(default_opts(), %{}))

    sw_name = Map.get(opts_map, :valve, "no_valve")

    task_term_rc = ExtraMod.task_abort({MOD, :fill})

    with %{pid: pid} <- task_term_rc do
      ["fill aborting ", inspect(task_term_rc)]
      |> ExtraMod.task_store_msg({MOD, :fill})

      rc = Switch.off(sw_name, wait_for_pid: pid, timeout_ms: 1500)
      [{:aborted, :reef_salt_mix, sw_name, rc}]
    else
      _anything -> [{:failed, task_term_rc}]
    end
  end

  def default_opts do
    [
      valve: "mixtank rodi",
      fill_time: [hours: 8],
      topoff_time: [hours: 1],
      valve_open: [minutes: 2, seconds: 48],
      valve_closed: [minutes: 17]
    ]
  end

  def kickstart(opts \\ []) when is_list(opts) do
    alias Reef.Salt.Fill, as: MOD

    sub = :fill

    with {:ok, task} <- ExtraMod.task_start({MOD, sub, :run, opts}),
         %{pid: pid} <- task do
      {sub, {:ok, pid}}
    else
      error -> {sub, error}
    end
  end

  @doc """
   Runs a task to fill the Salt Water Mix Tank
  """
  @doc since: "0.0.23"
  def run(opts \\ []) when is_list(opts) do
    alias Reef.Salt.Fill, as: MOD

    opts_map = Keyword.merge(default_opts(), opts) |> Enum.into(%{})

    with %{fill_duration: _} = cm <- make_control_map(opts_map) do
      rc = [fill_primary(cm), fill_final(cm)]

      ExtraMod.task_store_rc({MOD, :fill, rc})
      ["fill complete"] |> ExtraMod.task_store_msg({MOD, :fill})

      ExtraMod.task_put_state({MOD, :fill, Map.put(cm, :end, now())})
    else
      error -> error
    end
  end

  @doc """
   Retrieve the latest status message
  """
  @doc since: "0.0.23"
  def status(opts \\ []) do
    alias Reef.Salt.Fill, as: MOD

    ExtraMod.task_status({MOD, :fill}, opts)
  end

  ##
  ## Private
  ##

  defp fill_primary(%{start: s, fill_duration: d} = cm) do
    alias Reef.Salt.Fill, as: MOD

    ms = TimeSupport.duration_ms(d)
    elapsed = Duration.elapsed(now(), s)
    elapsed_ms = Duration.to_milliseconds(elapsed)

    # update the cycle count
    %{cycles: cys} = cm = Map.update(cm, :cycles, 1, fn x -> x + 1 end)

    ExtraMod.task_put_state({MOD, :fill, cm})

    [
      "fill starting cycle #",
      Integer.to_string(cys),
      " (elapsed time ",
      TimeSupport.humanize_duration(elapsed),
      ")"
    ]
    |> ExtraMod.task_store_msg({MOD, :fill})

    case elapsed_ms do
      # we have yet to pass the requesed runtime, do another cycle
      x when x < ms ->
        # add water to the salt water mix tank
        water_add(cm)

        # recharge the rodi tank
        water_recharge(cm)

        # call ourselves for another cycle
        fill_primary(cm)

      # enough time has elapsed, we're done
      _done ->
        [fill_primary: :done]
    end
  end

  defp fill_final(%{topoff_duration: duration} = cm) do
    ms = TimeSupport.duration_ms(duration)

    # fill part 2 (final fill) is trivial -- just open the rodi valve to
    # the saltwater mix tank for the duration requested
    rodi_valve(cm, :open)
    Process.sleep(ms)
    rodi_valve(cm, :closed)

    [fill_final: :done]
  end

  defp make_control_map(opts_map) do
    validate = fn
      %{fill_duration: _, topoff_duration: _, start: _} = x -> x
      _not_valid -> %{}
    end

    # build the base control map with the passed opts and :started
    base = %{start: now()}
    control_map = Map.merge(base, opts_map)

    # convert the :fill and :final opts to durations
    for {key, val} <- control_map, into: %{} do
      case key do
        :fill_time -> {:fill_duration, TimeSupport.duration(val)}
        :topoff_time -> {:topoff_duration, TimeSupport.duration(val)}
        key -> {key, val}
      end
    end
    |> validate.()
  end

  defp now, do: Duration.now()

  defp rodi_valve(%{valve: valve}, pos) when pos in [:open, :closed] do
    case pos do
      :open -> Switch.on(valve)
      :closed -> Switch.off(valve)
    end

    Process.sleep(1000)

    Switch.position(valve)
  end

  defp water_add(%{valve_open: opts} = cm) do
    ms = TimeSupport.duration_ms(opts)

    # open the valve to the salt water mix tank
    rodi_valve(cm, :open)

    # allow time to pass
    Process.sleep(ms)

    # close the valve to the salt water mix tank
    rodi_valve(cm, :closed)
  end

  defp water_recharge(%{valve_closed: opts} = cm) do
    ms = TimeSupport.duration_ms(opts)

    # for safety sake, ensure the valve is OFF
    rodi_valve(cm, :closed)

    # to recharge the rodi tank just let time pass
    Process.sleep(ms)
  end
end
