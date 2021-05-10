defmodule RuthSim.InboundMsg.Server do
  require Logger
  use GenServer

  defstruct init_args: %{}

  # must use RuthSim.Server after defstruct
  use RuthSim.Server

  @impl true
  def init(args) do
    %State{init_args: args} |> reply_ok()
  end

  @impl true
  def handle_call(msg, from, %State{} = s) do
    log_unmatched(msg, from, s)
  end

  @impl true
  # create a black hole host that will never process inbound messages
  def handle_cast({:process_msg, _via_mod, %{host: "ruth.blackhole"}}, %State{} = s) do
    noreply(s)
  end

  @impl true
  def handle_cast({:process_msg, via_mod, msg}, %State{} = s) do
    via_mod.inbound_cmd_msg(msg)

    noreply(s)
  end

  @impl true
  # received after a MQTT message of QoS1 has been delivered
  def handle_info({{MqttClient, :msg_published}, _ref, _rc}, %State{} = s), do: noreply(s)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
end
