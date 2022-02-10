defmodule Sally.Mqtt.Handler do
  @moduledoc """
  Mqtt Message Handler Callbacks
  """

  require Logger
  use Tortoise.Handler

  @env Application.compile_env(:sally, [:mqtt_connection, :filter_env])

  def init(args) do
    Logger.debug("#{inspect(args, pretty: true)}")
    %{env: @env, seen: %{hosts: MapSet.new()}, args: args} |> reply_ok()
  end

  @doc """
    Invokved when the MQTT client connection status changes

    The first parameter will be either :up or :down to indicate
    the status.
  """
  def connection(:up, %{args: args} = s) do
    Logger.debug("#{inspect(args, pretty: true)}")

    get_in(args, [:next_actions, :connected])
    |> List.wrap()
    |> reply_ok_next_action(s)
  end

  def connection(:down, s), do: reply_ok(s)
  def connection(:terminated, s), do: reply_ok(s)

  # NOTE: match and quietly ignore non-bitstring messages
  def handle_message(_topic, payload, s) when not is_bitstring(payload) do
    # TODO: log payload error

    reply_ok(s)
  end

  # NOTE: filter levels: [@filter_env, "r2", _host, _subsys, _cat | _extra]
  def handle_message([@env, "r2" | filter_rest], payload, s) do
    _ = Sally.Dispatch.accept(filter_rest, payload)

    {:ok, s}
  end

  def handle_message(topic_filters, payload, s) do
    unpacked = Msgpax.unpack(payload)

    [
      "\nunhandled filter:\n  ",
      Enum.join(topic_filters, "/"),
      "\npayload:\n  ",
      inspect(unpacked, pretty: true)
    ]
    |> Logger.info()

    reply_ok(s)
  end

  def subscription(:up, topic_filter, s) do
    Logger.debug("subscribed to: #{topic_filter}")

    reply_ok(s)
  end

  def terminate(reason, _state) do
    # tortoise doesn't care about what you return from terminate/2,
    # that is in alignment with other behaviours that implement a
    # terminate-callback
    Logger.info(["Tortoise terminate: ", inspect(reason)])
    :ok
  end

  defp reply_ok(%{} = s) when is_map(s), do: {:ok, s}
  defp reply_ok_next_action(actions, %{} = s) when is_list(actions), do: {:ok, s, actions}
end
