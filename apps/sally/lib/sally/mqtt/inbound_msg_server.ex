defmodule Sally.InboundMsg.Server do
  require Logger
  use GenServer, restart: :permanent, shutdown: 1000

  defstruct init_args: %{}
  alias __MODULE__, as: State

  @impl true
  def init(args) do
    %State{init_args: args} |> reply_ok()
  end

  @impl true
  def handle_cast({:process_msg, via_mod, msg}, %State{} = s) do
    via_mod.inbound_cmd_msg(msg)

    noreply(s)
  end

  @impl true
  # received after a MQTT message of QoS1 has been delivered
  def handle_info({{Sally.Mqtt.Client, :msg_published}, _ref, _rc}, %State{} = s), do: noreply(s)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  defp noreply(%State{} = s), do: {:noreply, s}
  # defp reply(res, %State{} = s), do: {:reply, res, s}
  defp reply_ok(%State{} = s), do: {:ok, s}
end
