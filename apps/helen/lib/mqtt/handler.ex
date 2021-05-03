defmodule Mqtt.Handler do
  @moduledoc """
  Mqtt Message Handler Callbacks
  """

  require Logger
  use Tortoise.Handler

  alias Mqtt.Client

  def init(args) do
    base_state = Enum.into(args, %{})
    extra_state = %{runtime_metrics: false, seen_topics: MapSet.new()}

    {:ok, Map.merge(base_state, extra_state)}
  end

  @doc """
    Invokved when the MQTT client connection status changes

    The first parameter will be either :up or :down to indicate
    the status.
  """
  def connection(:up, state) do
    Client.connected()

    {:ok, state}
  end

  def connection(:down, state) do
    Client.disconnected()

    {:ok, state}
  end

  def connection(:terminated, state) do
    Client.terminated()

    {:ok, state}
  end

  def handle_message([_env, "r", src_host] = topic, payload, state) do
    import Helen.Time.Helper, only: [utc_now: 0]

    %{payload: payload, topic: topic, host: src_host, msg_recv_dt: utc_now()}
    |> Mqtt.Inbound.handoff_msg()

    {:ok, state}
  end

  # def handle_message(
  #       [_env, "f", src_host, device] = topic,
  #       payload,
  #       state
  #     ) do
  #   %{payload: payload, topic: topic, src_host: src_host, device: device}
  #   |> Mqtt.Inbound.process()
  #
  #   {:ok, state}
  # end

  def handle_message(topic, payload, state) do
    [
      "default handle_msssage(): topic=",
      inspect(topic),
      " payload=",
      inspect(payload, pretty: true),
      " state=",
      inspect(pretty: true)
    ]
    |> Logger.warn()

    {:ok, state}
  end

  def subscription(:up, topic_filter, state) do
    [
      "subscribed to reporting topic: ",
      inspect(topic_filter, pretty: true)
    ]
    |> Logger.info()

    {:ok, state}
  end

  def subscription(status, topic_filter, state) do
    [
      "subscription ",
      inspect(topic_filter, pretty: true),
      " status ",
      inspect(status, pretty: true)
    ]
    |> Logger.warn()

    {:ok, state}
  end

  def terminate(reason, _state) do
    # tortoise doesn't care about what you return from terminate/2,
    # that is in alignment with other behaviours that implement a
    # terminate-callback
    Logger.warn(["Tortoise terminate: ", inspect(reason)])
    :ok
  end
end
