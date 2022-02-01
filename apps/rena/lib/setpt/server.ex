defmodule Rena.SetPt.Server do
  require Logger
  use GenServer

  alias __MODULE__
  alias Rena.SetPt.State

  @impl true
  def init(args) do
    init_args_fn = args[:init_args_fn]
    server_name = args[:server_name]

    if server_name do
      Process.register(self(), server_name)

      # NOTE:
      # 1. init_args_fn, when available, is the sole provider of args so
      #    we must add server_name to the returned args
      #
      # 2. otherwise simply use the args passed in

      if(init_args_fn, do: init_args_fn.(server_name: server_name), else: args)
      |> then(fn final_args -> {:ok, State.new(final_args), {:continue, :bootstrap}} end)
    else
      {:stop, :missing_server_name}
    end
  end

  @doc false
  def child_spec(opts) do
    # :id is for the Supervisor so remove it from opts
    {id, opts_rest} = Keyword.pop(opts, :id)
    {restart, opts_rest} = Keyword.pop(opts_rest, :restart, :permanent)

    # init/1 requires server_name, add to opts
    final_opts = [{:server_name, id} | opts_rest]

    # build the final child_spec map
    %{id: id, start: {Server, :start_link, [final_opts]}, restart: restart}
  end

  @doc false
  def start_link(start_args) do
    GenServer.start_link(Server, start_args)
  end

  @impl true
  def handle_call(:pause, _from, %State{} = s) do
    State.pause_notifies(s) |> reply_ok()
  end

  @impl true
  def handle_continue(:bootstrap, %State{} = s) do
    State.start_notifies(s) |> noreply()

    # NOTE: at this point the server is running and no further actions occur until an
    #       equipment notification is received
  end

  # NOTE: missing: true messages are not sent by default, no need to handle them
  @impl true
  def handle_info({Alfred, %Alfred.Memo{missing?: false} = memo}, %State{} = s) do
    # NOTE: only compute sensor results and potentially execute a command
    # when a transition is allowed
    if Rena.SetPt.State.allow_transition?(s) do
      opts = [alfred: s.alfred, server_name: s.server_name]
      sensor_results = Rena.Sensor.range_compare(s.sensors, s.sensor_range, opts)

      memo.name
      |> Rena.SetPt.Cmd.make(sensor_results, opts)
      |> Rena.SetPt.Cmd.effectuate(opts)
      |> Rena.SetPt.State.update_last_exec(s)
      |> noreply()
    else
      Rena.SetPt.State.update_last_notify_at(s) |> noreply()
    end
  end

  @impl true
  def handle_info({Alfred, %Alfred.Track{} = track}, %State{} = s) do
    case track do
      %{rc: :ok} -> State.update_last_exec(track.at.released, s)
      %{rc: rc} -> ack_fail(s, ack_fail: true, rc: rc) |> State.update_last_exec(:failed)
    end
    |> noreply()
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp ack_fail(%{equipment: name} = s, tags), do: Betty.app_error(s, [{:equipment, name} | tags])

  defp noreply(%State{} = s), do: {:noreply, s}
  defp noreply({:stop, :normal, s}), do: {:stop, :normal, s}
  defp reply_ok(%State{} = s), do: {:reply, :ok, s}
end
