defmodule PulseWidth.Msg do
  require Logger

  alias PulseWidth.DB.{Command, Device}
  alias PulseWidth.States

  # @debug true

  # (1 of 3) nominal case
  # NOTE: the match on pio_count is only necessary until Ruth firmware is
  # updated to match v0.9.9
  def handle(%{processed: false, type: "pwm", pio_count: _} = msg_in) do
    # pass the results of the wrapped txn and the original msg for final deposition
    :timer.tc(fn -> Repo.transaction(fn -> wrapped(msg_in) end, []) end) |> finalize_msg(msg_in) |> log()
  end

  # (2 of 3) handle messages from legacy Ruth firmware
  def handle(
        %{
          processed: false,
          host: <<"ruth."::utf8, _::binary>>,
          device: <<"pwm"::utf8, _::binary>> = legacy
        } = msg_in
      ) do
    parts = map_legacy_device(legacy)

    if is_nil(parts[:device]) do
      Logger.info("legacy device: #{legacy} parts: #{inspect(parts, pretty: true)}")

      put_in(msg_in.processed, true)
    else
      put_in(msg_in, [:device], parts[:device]) |> put_in([:pio_count], 4) |> handle()
    end
  end

  # (3 or 3) if the primary handle_message does not match then simply return the msg
  # since it wasn't for switch and/or has already been processed in the
  # pipeline
  def handle(msg_in), do: msg_in

  def map_legacy_device(legacy) do
    re = ~r/(?<device>pwm\/[a-z]+-?[a-z]+)\.pin:(?<pio>\d)/

    parts = Regex.named_captures(re, legacy, capture: :all_names)

    %{device: parts["device"], pio: parts["pio"]}
  end

  defp add_fault_checks(msg) do
    %{msg | fault_checks: [msg.fault_checks, :pwm_rc, :device, :states_rc, :cmd_rc] |> List.flatten()}
  end

  defp finalize_msg(txn_res, msg_in) do
    case txn_res do
      {elapsed, {:ok, msg_final}} ->
        success_rc = {:ok, [elapsed_ms: elapsed / 1000.0]}

        msg_final |> put_pwm_rc(success_rc)

      {_elapsed, error} ->
        failed_rc = {:failed, inspect(error, pretty: true)}
        msg_in |> put_pwm_rc(failed_rc)
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

    # @debug && ["\n", inspect(ctx, pretty: true), "\n"] |> Logger.info()
    ctx
  end

  defp put_pwm_rc(msg, what), do: put_in(msg, [:pwm_rc], what) |> message_processed()

  defp wrapped(msg_in) do
    msg_in
    |> add_fault_checks()
    |> Device.upsert()
    |> States.inbound_msg()
    |> Command.ack_if_needed()
    |> Command.release()
  end
end
