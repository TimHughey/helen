defmodule Sally.Mqtt.Handler do
  @moduledoc """
  Mqtt Message Handler Callbacks
  """

  require Logger
  use Tortoise.Handler

  def init(args) do
    Logger.debug("#{inspect(args, pretty: true)}")
    %{seen: %{hosts: MapSet.new()}, args: args} |> reply_ok()
  end

  @doc """
    Invokved when the MQTT client connection status changes

    The first parameter will be either :up or :down to indicate
    the status.
  """
  def connection(:up, %{args: args} = s) do
    # Client.connected()

    Logger.debug("#{inspect(args, pretty: true)}")

    get_in(args, [:next_actions, :connected])
    |> List.wrap()
    |> reply_ok_next_action(s)
  end

  def connection(:down, s) do
    # Client.disconnected()

    reply_ok(s)
  end

  def connection(:terminated, s) do
    # Client.terminated()

    reply_ok(s)
  end

  # @known_envs ["dev", "test", "prod"]
  # defp check_metadata(%Msg{env: env} = m) when env not in @known_envs do
  #   invalid(m, "unknown env filter")
  # end

  def handle_message(_topic, payload, s) when not is_bitstring(payload) do
    # TODO: log payload error

    reply_ok(s)
  end

  def handle_message([env, "r", host_ident, subsystem, category | extra], payload, s) do
    alias Sally.Dispatch

    store_last = fn x -> put_in(s, [:last], x) end

    {[env, host_ident, subsystem, category, extra], payload}
    |> Dispatch.accept()
    |> Dispatch.handoff()
    |> store_last.()
    |> reply_ok()
  end

  def handle_message(topic_filters, payload, s) do
    unpacked = Msgpax.unpack(payload)
    Logger.info("unhandled message: #{Enum.join(topic_filters, "/")}\n#{inspect(unpacked, pretty: true)}")
    Logger.info(inspect(topic_filters))

    reply_ok(s)
  end

  # def handle_message(topic, _payload, s) do
  #   Logger.warn("unhandled topic: #{Enum.join(topic, "/")}")
  #
  #   reply_ok(s)
  # end

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

  defp reply_ok(s) when is_map(s) do
    {:ok, s}
  end

  defp reply_ok_next_action(actions, s) when is_list(actions) and is_map(s) do
    {:ok, s, actions}
  end
end
