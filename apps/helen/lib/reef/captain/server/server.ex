defmodule Reef.Captain.Server do
  @moduledoc """
  Orchestration of Reef Activities (e.g. salt mix, cleaning)
  """

  use GenServer, restart: :transient, shutdown: 7000
  use Helen.Worker.Logic

  # alias Reef.FirstMate.Server, as: FirstMate
  # alias Reef.MixTank
  # alias Reef.MixTank.{Air, Pump, Rodi}

  ##
  ## GenServer Start and Initialization
  ##

  @doc false
  @impl true
  def init(args) do
    import Reef.Captain.Opts, only: [parsed: 0]

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

  A single key (e.g. :server_mode) or a list of keys (e.g. :worker_mode, :server_mode)
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

  ##
  ## GenServer handle_* callbacks
  ##

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

  # defp __all_stop__(state) do
  #   import Reef.Logic, only: [change_token: 1]
  #
  #   state
  #   # prevent processing of any lingering messages
  #   |> change_token()
  #   # the safest way to stop everything is to take all the crew offline
  #   |> crew_offline()
  #   # bring them back online so they're ready for whatever comes next
  #   |> crew_online()
  #   |> set_all_modes_ready()
  # end

  # defp crew_list, do: [Air, Pump, Rodi, MixTank.Temp]
  # defp crew_list_no_heat, do: [Air, Pump, Rodi]
  #
  # # NOTE:  state is unchanged however is parameter for use in pipelines
  # defp crew_offline(state) do
  #   for crew_member <- crew_list() do
  #     apply(crew_member, :mode, [:standby])
  #   end
  #
  #   state
  # end
  #
  # # NOTE:  state is unchanged however is parameter for use in pipelines
  # defp crew_online(state) do
  #   # NOTE:  we NEVER bring MixTank.Temp online unless explictly requested
  #   #        in a mode step/cmd
  #   for crew_member <- crew_list_no_heat() do
  #     apply(crew_member, :mode, [:active])
  #   end
  #
  #   state
  # end

  defp msg_puts(state, msg) do
    """
     ==> #{inspect(msg)}

    """
    |> IO.puts()

    state
  end
end
