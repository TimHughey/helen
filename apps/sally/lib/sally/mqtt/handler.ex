defmodule Sally.Mqtt.Handler do
  @moduledoc """
  Mqtt Message Handler Callbacks
  """

  require Logger
  use Tortoise.Handler

  alias Sally.InboundMsg
  alias Sally.Mqtt.Client
  alias Sally.MsgIn

  def init(args) do
    %{seen: %{hosts: MapSet.new()}, args: args} |> reply_ok()
  end

  @doc """
    Invokved when the MQTT client connection status changes

    The first parameter will be either :up or :down to indicate
    the status.
  """
  def connection(:up, %{args: args} = s) do
    Client.connected()

    get_in(args, [:next_actions, :connected])
    |> List.wrap()
    |> reply_ok_next_action(s)
  end

  def connection(:down, s) do
    Client.disconnected()

    reply_ok(s)
  end

  def connection(:terminated, s) do
    Client.terminated()

    reply_ok(s)
  end

  def handle_message([env, "r", src_host, type], payload, s) do
    %MsgIn{
      payload: payload,
      env: env,
      host: src_host,
      type: type,
      at: DateTime.utc_now()
    }
    |> MsgIn.preprocess()
    |> InboundMsg.handoff_msg()

    reply_ok(s)
  end

  def handle_message(topic, _payload, s) do
    Logger.warn("unhandled topic: #{Enum.join(topic, "/")}")

    reply_ok(s)
  end

  def subscription(:up, topic_filter, s) do
    Logger.debug("subscribed to reporting topic: #{inspect(topic_filter)}")

    reply_ok(s)
  end

  def terminate(reason, _state) do
    # tortoise doesn't care about what you return from terminate/2,
    # that is in alignment with other behaviours that implement a
    # terminate-callback
    Logger.warn(["Tortoise terminate: ", inspect(reason)])
    :ok
  end

  defp reply_ok(s) when is_map(s) do
    {:ok, s}
  end

  defp reply_ok_next_action(actions, s) when is_list(actions) and is_map(s) do
    {:ok, s, actions}
  end
end
