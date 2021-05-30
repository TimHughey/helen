defmodule Sally.Mqtt do
  require Logger

  alias Sally.MsgOut

  def publish(%MsgOut{} = mo) do
    %MsgOut{mo | topic: MsgOut.ensure_topic(mo), packed: MsgOut.pack(mo)} |> call()
  end

  def seen_topics do
    %{seen_topics: topics} = :sys.get_state(Sally.InboundMsg.Server)

    MapSet.to_list(topics) |> Enum.sort()
  end

  defp call(%MsgOut{} = mo) do
    case Process.whereis(mo.server) do
      pid when is_pid(pid) -> GenServer.call(pid, {:publish, mo})
      _ -> {:no_server, mo}
    end
  end

  # def wait_for_roundtrip(%{roundtrip_ref: ref} = ctx) do
  #   ctx |> put_in([:roundtrip_rc], wait_for_roundtrip(ref)) |> Map.delete(:roundtrip_ref)
  # end
  #
  # def wait_for_roundtrip(ctx) when is_map(ctx), do: ctx
  #
  # def wait_for_roundtrip(ref) when is_binary(ref) do
  #   case GenServer.call(Mqtt.Inbound, {:wait_for_roundtrip_ref, ref}) do
  #     :already_received ->
  #       {:already_received, ref}
  #
  #     :added_to_waiters ->
  #       receive do
  #         {{Mqtt.Inbound, :roundtrip}, ^ref} when is_binary(ref) ->
  #           {:waited_and_received, ref}
  #       after
  #         10_000 ->
  #           {:roundtrip_timeout, ref}
  #       end
  #   end
  # end
end
