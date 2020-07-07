defmodule Roost do
  @moduledoc false

  # @compile {:no_warn_undefined, PulseWidth}

  alias PulseWidth
  use Timex

  use GenServer, restart: :transient, shutdown: 5000
  use Helen.Module.Config

  ##
  ## GenServer init and start
  ##

  @impl true
  def init(args) do
    import Helen.Time.Helper, only: [epoch: 0]
    config_opts = config_opts(args)

    state = %{
      dance: :init,
      opts: config_opts,
      last_timeout: epoch(),
      timeouts: 0,
      token: 1
    }

    {:ok, state}
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  ##
  ## Public API for GenServer related functions
  ##

  @doc """
  Is this server alive?
  """
  @doc since: "0.0.27"
  def alive? do
    case GenServer.whereis(__MODULE__) do
      nil -> false
      pid when is_pid(pid) -> true
      _anything -> false
    end
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
    keys = [keys] |> List.flatten()
    state = GenServer.call(__MODULE__, :state)

    case keys do
      [] -> state
      [x] -> Map.get(state, x)
      x -> Map.take(state, [x] |> List.flatten())
    end
  end

  def timeouts, do: state(:timeouts)

  ##
  ## Roost Public API
  ##

  def all_stop do
    GenServer.call(__MODULE__, {:all_stop})
  end

  def dance_with_me do
    GenServer.call(__MODULE__, {:dance})
  end

  def leaving(opts \\ "PT10M0.0S") do
    GenServer.call(__MODULE__, {:leaving, opts})
  end

  def opts, do: Map.get(state(), :opts)

  @doc false
  @impl true
  def handle_call(:state, _from, s), do: reply(s, s)

  @impl true
  def handle_call({:all_stop}, _from, state) do
    state
    |> all_stop()
    |> reply(:answering_all_stop)
  end

  @impl true
  def handle_call({:dance}, _from, state) do
    PulseWidth.duty_names_begin_with("roost lights", duty: 8191)
    PulseWidth.duty_names_begin_with("roost el wire entry", duty: 8191)

    PulseWidth.duty("roost el wire", duty: 4096)

    led_forest_cmd_map = %{
      name: "medium slow fade",
      activate: true,
      random: %{
        min: 256,
        max: 2048,
        primes: 10,
        step_ms: 50,
        step: 7,
        priority: 7
      }
    }

    PulseWidth.random("roost led forest", led_forest_cmd_map)
    PulseWidth.duty("roost disco ball", duty: 5500)

    state = change_token(state)

    Process.send_after(self(), {:timer, :slow_discoball, state[:token]}, 15000)

    state
    |> put_in([:active_cmd], :spinning_up)
    |> reply(:spinning_up)
  end

  @impl true
  def handle_call({:leaving, opts}, _from, state) do
    import Helen.Time.Helper, only: [to_ms: 1]

    PulseWidth.duty_names_begin_with("roost lights", duty: 0)
    PulseWidth.off("roost el wire")
    PulseWidth.off("roost disco ball")

    PulseWidth.duty("roost led forest", duty: 8191)
    PulseWidth.duty("roost el wire entry", duty: 8191)

    state = change_token(state)

    Process.send_after(self(), {:timer, :all_stop, state[:token]}, to_ms(opts))

    state
    |> put_in([:active_cmd], :leaving)
    |> reply(:goodbye)
  end

  @impl true
  def handle_info({:timer, cmd, msg_token}, %{token: token} = state)
      when msg_token == token do
    case cmd do
      :slow_discoball ->
        PulseWidth.duty("roost disco ball", duty: 5100)

        state
        |> put_in([:active_cmd], :dancing)
        |> put_in([:dance], :yes)
        |> noreply()

      :all_stop ->
        all_stop(state)
        |> noreply()
    end
  end

  # NOTE:  when the msg_token does not match the state token then
  #        a change has occurred and this message should be ignored
  @impl true
  def handle_info({:timer, _msg, msg_token}, %{token: token} = s)
      when msg_token != token do
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
  ## Private
  ##

  defp all_stop(state) do
    PulseWidth.off("roost disco ball")
    PulseWidth.duty_names_begin_with("roost lights", duty: 0)
    PulseWidth.duty_names_begin_with("roost el wire", duty: 0)

    led_forest_cmd_map = %{
      activate: true,
      name: "dim slow fade",
      random: %{
        min: 256,
        max: 768,
        primes: 10,
        step_ms: 50,
        step: 7,
        priority: 7
      }
    }

    PulseWidth.random("roost led forest", led_forest_cmd_map)

    state
    |> change_token()
    |> put_in([:dance], :no)
    |> put_in([:active_cmd], :none)
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
  # defp reply(val, s), do: {:reply, val, s, loop_timeout(s)}

  # defp reply_and_merge(s, m, val) when is_map(s) and is_map(m),
  #   do: reply(Map.merge(s, m), val)
end
