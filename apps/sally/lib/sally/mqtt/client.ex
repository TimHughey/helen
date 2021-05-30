defmodule Sally.Mqtt.Client do
  @moduledoc false

  require Logger
  use GenServer, restart: :permanent, shutdown: 1000

  alias Sally.Mqtt.Client.State, as: State

  ##
  ## GenServer Start and Initialization
  ##

  @impl true
  def init(init_args) when is_list(init_args) do
    # prepare the opts that will be passed to Tortoise and start it

    %State{
      client_id: init_args[:client_id],
      runtime_metrics: init_args[:runtime_metrics]
    }
    |> reply_ok()
  end

  def start_link(start_args) do
    GenServer.start_link(__MODULE__, start_args, name: __MODULE__)
  end

  ##
  ## Handler Connection Callbacks
  ##
  def connected do
    GenServer.cast(__MODULE__, {:connected})
  end

  def disconnected do
    GenServer.cast(__MODULE__, {:disconnected})
  end

  def terminated do
    GenServer.cast(__MODULE__, {:terminated})
  end

  @impl true
  def handle_call({:publish, %Sally.MsgOut{} = mo}, _from, %State{} = s) do
    last_pub = :timer.tc(fn -> Tortoise.publish(s.client_id, mo.topic, mo.packed, qos: mo.qos) end)

    # TODO add Betty

    {_elapsed, pub_rc} = last_pub

    pub_ref = if is_tuple(pub_rc), do: elem(pub_rc, 1), else: nil

    %State{s | last_pub: last_pub} |> reply(pub_ref)
  end

  @impl true
  def handle_cast({:connected}, %State{} = s) do
    %State{s | connected: true} |> noreply()
  end

  @impl true
  def handle_cast({event}, s) when event in [:disconnected, :terminated] do
    %State{s | connected: false} |> noreply()
  end

  @impl true
  def handle_info({{Tortoise, _client_id}, _ref, _res}, %State{} = s) do
    s |> noreply()
  end

  defp noreply(%State{} = s), do: {:noreply, s}
  defp reply(%State{} = s, x), do: {:reply, x, s}
  defp reply_ok(%State{} = s), do: {:ok, s}
end
