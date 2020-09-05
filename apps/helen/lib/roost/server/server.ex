defmodule Roost.Server do
  @moduledoc false

  # @compile {:no_warn_undefined, PulseWidth}

  alias PulseWidth
  use Timex

  use GenServer, restart: :transient, shutdown: 5000
  use Helen.Worker.Logic

  ##
  ## GenServer init and start
  ##

  @impl true
  def init(args) do
    import Roost.Opts, only: [parsed: 0]

    # just in case we were passed a map?!?
    args = Enum.into(args, [])
    opts = parsed()

    state = %{
      module: __MODULE__,
      server: %{
        mode: args[:server_mode] || :active,
        standby_reason: :none,
        faults: %{}
      },
      opts: opts,
      timeouts: %{last: :never, count: 0},
      token: nil,
      token_at: nil
    }

    # should the server start?
    if state[:server][:mode] == :standby do
      :ignore
    else
      {:ok, state, {:continue, :bootstrap}}
    end
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  ##
  ## Public API
  ##

  @doc """
  Return the GenServer state.

  A single key (e.g. :server_mode) or a list of keys (e.g. :logic, :server_mode)
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

  @doc false
  @impl true
  def handle_call({:all_stop}, _from, state) do
    alias Helen.Worker.Logic

    state
    |> Logic.all_stop()
    |> reply(:answering_all_stop)
  end

  @doc false
  @impl true
  def handle_call({:cancel_delayed_cmd}, _from, state) do
    timer = get_in(state, [:pending, :delayed])

    if is_reference(timer), do: Process.cancel_timer(timer)

    state
    |> put_in([:pending], %{})
    |> reply(:ok)
  end

  @doc false
  @impl true
  def handle_call({:mode, mode, _api_opts}, _from, state) do
    state
    |> change_mode(mode)
    |> check_fault_and_reply()
  end

  @doc false
  @impl true
  def handle_call(msg, _from, state),
    do: state |> msg_puts(msg) |> reply({:unmatched_msg, msg})

  @impl true
  def handle_info(
        {:msg, {:mode, mode}, msg_token},
        %{token: token} = state
      )
      when msg_token == token do
    state
    |> change_mode(mode)
    |> noreply()
  end

  @doc false
  @impl true
  def handle_info({:msg, _msg, msg_token}, %{token: token} = state)
      when msg_token != token,
      do: state |> noreply()

  @doc false
  @impl true
  def handle_info({:timer, _cmd, msg_token}, %{token: token} = state)
      when msg_token == token do
    state |> noreply()
  end

  # NOTE:  when the msg_token does not match the state token then
  #        a change has occurred and this message should be ignored
  @doc false
  @impl true
  def handle_info({:timer, _msg, msg_token}, %{token: token} = state)
      when msg_token != token do
    state |> noreply()
  end

  ##
  ## PRIVATE
  ##

  defp msg_puts(state, msg) do
    """
     ==> #{inspect(msg)}

    """
    |> IO.puts()

    state
  end
end
