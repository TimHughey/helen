defmodule Switch.Msg do
  require Logger

  alias Switch.DB.{Command, Device}
  alias Switch.States

  # @debug true

  def handle(%{processed: false, type: "switch"} = msg_in) do
    # pass the results of the wrapped txn and the original msg for final deposition
    :timer.tc(fn -> Repo.transaction(fn -> wrapped(msg_in) end, []) end) |> finalize_msg(msg_in) |> log()
  end

  defp add_fault_checks(msg) do
    %{msg | fault_checks: [msg.fault_checks, :switch_rc, :device, :states_rc, :cmd_rc] |> List.flatten()}
  end

  defp finalize_msg(txn_res, msg_in) do
    case txn_res do
      {elapsed, {:ok, msg_final}} ->
        success_rc = {:ok, [elapsed_ms: elapsed / 1000.0]}

        msg_final |> put_switch_rc(success_rc)

      {_elapsed, error} ->
        failed_rc = {:failed, inspect(error, pretty: true)}
        msg_in |> put_switch_rc(failed_rc)
    end
  end

  defp message_processed(msg), do: %{msg | processed: true}

  defp log(%{fault_checks: checks} = ctx) do
    for check <- checks do
      case get_in(ctx, [check]) do
        {:ok, _} ->
          :no_fault

        {rc, fault} ->
          [
            "#{inspect(check)} fault detected: #{inspect(rc)}\n",
            (is_binary(fault) && fault) || inspect(fault, pretty: true),
            "\n"
          ]
          |> Logger.warn()
      end
    end

    Logger.debug(["\n", inspect(ctx, pretty: true)])
    ctx
  end

  defp put_switch_rc(msg, what), do: put_in(msg, [:switch_rc], what) |> message_processed()

  defp wrapped(msg_in) do
    msg_in
    |> add_fault_checks()
    |> Device.upsert()
    |> States.inbound_msg()
    |> Command.ack_if_needed()
    |> Command.release()
  end
end
