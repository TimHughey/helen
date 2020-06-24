defmodule Roost do
  @moduledoc false

  # @compile {:no_warn_undefined, PulseWidth}

  alias PulseWidth
  use Timex

  use GenServer, restart: :transient, shutdown: 5000
  use Helen.Module.Config

  def abort(_) do
    message = """

    ***
    *** aborting #{inspect(self())}
    ***

    """

    IO.puts(message)
    Process.exit(self(), :normal)
  end

  ##
  ## GenServer init and start
  ##

  @impl true
  def init(args) do
    config_opts = config_opts(args)

    state = %{opts: config_opts}

    {:ok, state}
  end

  def start_link(args) do
    GenServer.start_link(Roost, args, name: Roost)
  end

  ##
  ## Public API for GenServer related functions
  ##

  def restart, do: Supervisor.restart_child(ExtraMod.Supervisor, Roost)

  def state, do: :sys.get_state(Roost)

  def stop, do: Supervisor.terminate_child(ExtraMod.Supervisor, Roost)

  ##
  ## Roost Public API
  ##

  def closing(opts \\ [minutes: 5]) do
    GenServer.call(__MODULE__, {:closing, opts})
  end

  def close_now do
    Process.send(Roost, {:closed}, [])
  end

  def open do
    GenServer.call(__MODULE__, {:open})
  end

  def opts, do: Map.get(state(), :opts)

  @impl true
  def handle_call({:open}, _from, s) do
    PulseWidth.duty_names_begin_with("roost lights", duty: 8191)
    PulseWidth.duty_names_begin_with("roost el wire entry", duty: 8191)

    PulseWidth.duty("roost el wire", duty: 4096)
    PulseWidth.duty("roost led forest", duty: 200)
    PulseWidth.duty("roost disco ball", duty: 5200)

    # put the next messgage to send in the state and set the timeout
    # to allow the disco ball to spin up
    {:reply, :spinning_up, Map.put(s, :next_msg, {:open_part2}), 5000}
  end

  @impl true
  def handle_call({:closing, opts}, _from, s) do
    PulseWidth.duty_names_begin_with("roost lights", duty: 0)
    PulseWidth.off("roost el wire")
    PulseWidth.off("roost disco ball")

    PulseWidth.duty("roost led forest", duty: 8191)
    PulseWidth.duty("roost el wire entry", duty: 8191)

    PulseWidth.duty_names_begin_with("front", duty: 0.03)

    closing_ms = duration_ms(opts)

    {:reply, :closing_sequence_initiated, Map.put(s, :next_msg, {:closed}),
     closing_ms}
  end

  @impl true
  def handle_info(:timeout, s) do
    {next_msg, state} = Map.pop(s, :next_msg, false)

    if next_msg do
      Process.send(self(), next_msg, [])
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:closed}, s) do
    PulseWidth.off("roost disco ball")
    PulseWidth.duty_names_begin_with("roost lights", duty: 0)
    PulseWidth.duty_names_begin_with("roost el wire", duty: 0)

    PulseWidth.duty("roost led forest", duty: 0.02)
    PulseWidth.duty_names_begin_with("front", duty: 0.03)

    {:noreply, Map.merge(s, %{roost_open: false, next_msg: nil})}
  end

  @impl true
  def handle_info({:open_part2}, s) do
    PulseWidth.duty("roost disco ball", duty: 4500)

    {:noreply, Map.put(s, :roost_open, true)}
  end

  defp duration(opts) when is_list(opts) do
    # after hours of searching and not finding an existing capabiility
    # in Timex we'll roll our own consisting of multiple Timex functions.
    ~U[0000-01-01 00:00:00Z]
    |> Timex.shift(Keyword.take(opts, valid_duration_opts()))
    |> Timex.to_gregorian_microseconds()
    |> Duration.from_microseconds()
  end

  defp duration(_anything), do: 0

  defp duration_ms(opts) when is_list(opts),
    do: duration(opts) |> Duration.to_milliseconds(truncate: true)

  defp valid_duration_opts,
    do: [
      :microseconds,
      :seconds,
      :minutes,
      :hours,
      :days,
      :weeks,
      :months,
      :years
    ]
end
