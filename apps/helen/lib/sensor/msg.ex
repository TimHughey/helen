defmodule Sensor.Msg do
  require Logger

  alias Sensor.DataPoint.Fact
  alias Sensor.DataPoints

  alias Sensor.DB.Device

  @results_rc_key :sensor_rc

  # @debug true

  # (1 of 2) nominal case, this is a sensor message
  def handle(%{type: "sensor"} = msg_in) do
    msg_ready = add_fault_checks(msg_in)

    # pass msg_ready to make_rc for use in the event of txn failure
    :timer.tc(fn -> wrapped_txn(msg_ready) end, [])
    |> make_rc(msg_ready)
    |> Fact.write_metric()
    |> check_faults()
  end

  # (2 or 2) pass through unmatched messages
  def handle(msg_in), do: msg_in

  defp add_fault_checks(msg) do
    checks = [:sensor_rc, :device, :datapoints_rc, msg.fault_checks] |> List.flatten()

    %{msg | processed: true, fault_checks: checks}
  end

  # NOTE! this function passes through msg_out unchanged
  defp check_faults(%{fault_checks: checks} = msg_out) do
    for check <- checks, do: get_in(msg_out, [check]) |> log_fault(check)

    Logger.info([inspect(msg_out, pretty: true)])

    msg_out
  end

  # (1 of 2) not a fault
  defp log_fault({:ok, _}, _check), do: nil

  defp log_fault({rc, fault}, check) do
    # avoid making binaries pretty

    check_bin = inspect(check)
    rc_bin = inspect(rc)
    fault_bin = (is_binary(fault) && fault) || inspect(fault, pretty: true)

    [check_bin, " fault detected: ", rc_bin, "\n", fault_bin, "\n"] |> Logger.warn()
  end

  # co-located to make_rc/2
  defp add_elapsed(list, elapsed), do: Keyword.put(list, :elapsed_ms, elapsed / 1000.0)

  # (1 of 2) success!  final rc is {:ok, [elapsed_ms: txn_elapsed_ms]}
  defp make_rc({elapsed, {:ok, msg_final}}, _msg_ready) do
    put_in(msg_final, [@results_rc_key], {:ok, add_elapsed([], elapsed)})
  end

  # (2 of 2) failed... final rc is {:failed, [error: error, elapsed_ms: txn_elapsed_ms]}
  defp make_rc({elapsed, error}, msg_ready) do
    put_in(msg_ready, [@results_rc_key], {:failed, [error: error] |> add_elapsed(elapsed)})
  end

  defp wrapped_txn(msg_ready) do
    Repo.transaction(fn ->
      Repo.checkout(fn ->
        msg_ready
        |> Device.upsert()
        |> DataPoints.inbound_msg()
      end)
    end)
  end
end
