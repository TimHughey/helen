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
    Logger.debug("#{inspect(args, pretty: true)}")

    get_in(args, [:next_actions, :connected])
    |> List.wrap()
    |> reply_ok_next_action(s)
  end

  def connection(:down, s), do: reply_ok(s)
  def connection(:terminated, s), do: reply_ok(s)

  # NOTE: match 'odd' messages (e.g. payload is not a bitstring) first
  def handle_message(_topic, payload, s) when not is_bitstring(payload) do
    # TODO: log payload error

    reply_ok(s)
  end

  def handle_message([_env, "r2", _host, _subsys, _cat | _extra] = filter, payload, s) do
    process_dispatch(filter, payload)
    |> then(fn last_dispatch -> Map.put(s, :last, last_dispatch) end)
    |> reply_ok()
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

  def process_dispatch([env, "r2", host_ident, subsystem, category | extra], payload) do
    {[env, host_ident, subsystem, category, extra], payload}
    |> Sally.Dispatch.accept()
    |> Sally.Dispatch.preprocess()
    |> Sally.Dispatch.handoff()
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
