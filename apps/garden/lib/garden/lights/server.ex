defmodule Lights.Server do
  @moduledoc false

  require Logger
  use GenServer

  use Garden.Server
  alias Lights.{Config, Helpers, Logic}

  import Helpers, only: [noreply: 1, reply: 2, server_name: 1]

  def alive?(args \\ []) do
    case GenServer.whereis(server_name(args)) do
      x when is_pid(x) -> true
      nil -> false
    end
  end

  def call(msg, args \\ []) do
    if alive?(args) do
      GenServer.call(server_name(args), msg)
    else
      :no_server
    end
  end

  def start_link(args) do
    args = ensure_server_args(args)
    GenServer.start_link(args[:mod], args, name: args[:name])
  end

  @impl true
  def init(args) do
    {:ok, initial_state(args), {:continue, :startup}}
  end

  @impl true
  def terminate(reason, _s) do
    Logger.debug(["reason: ", inspect(reason, pretty: true)])
    :ok
  end

  @impl true
  def handle_call(:cfg, _from, %{cfg: cfg} = s) do
    reply(cfg, s)
  end

  @impl true
  def handle_call(:load_cfg, _from, s) do
    import Lights.Config, only: [reload_if_needed: 1]
    reply(:ok, reload_if_needed(s))
  end

  @impl true
  def handle_call(:timeouts, _from, s) do
    import Lights.Helpers, only: [get_timeouts: 1, reply: 2]

    reply(get_timeouts(s), s)
  end

  @impl true
  def handle_call(oops, _from, s), do: reply({:bad_call, oops}, s)

  @impl true
  def handle_cast(oops, s) do
    import Lights.Helpers, only: [noreply: 1, pretty: 1]
    Logger.debug("unhandled msg:#{pretty(oops)}state:#{pretty(s)}")

    noreply(s)
  end

  @impl true
  def handle_continue(step, %{args: _} = s) do
    import Config, only: [reload_if_needed: 1]
    import Lights.Helpers, only: [change_token: 1, noreply: 1]
    import Logic, only: [run: 1, schedule_run: 1]

    case step do
      :startup -> {:noreply, s, {:continue, :wait_suninfo}}
      :wait_suninfo -> {:noreply, s, {:continue, check_suninfo()}}
      :load_cfg -> {:noreply, reload_if_needed(s), {:continue, :run}}
      :run -> change_token(s) |> run() |> schedule_run() |> noreply()
    end
  end

  @impl true
  def handle_info(:run, state) do
    import Helpers, only: [noreply: 1, update_last_run: 1]
    import Logic, only: [run: 1, schedule_run: 1]

    state
    |> run()
    |> update_last_run()
    |> schedule_run()
    |> noreply()
  end

  @impl true
  def handle_info(:timeout, state) do
    import Helpers, only: [noreply: 1, update_last_timeout: 1]
    import Logic, only: [timeout_hook: 1]

    state
    |> timeout_hook()
    |> update_last_timeout()
    |> noreply()
  end

  defp check_suninfo do
    import Agnus, only: [sun_info: 1]

    case sun_info(:sunrise) do
      %DateTime{} ->
        :load_cfg

      false ->
        Process.sleep(10)
        :wait_suninfo
    end
  end
end
