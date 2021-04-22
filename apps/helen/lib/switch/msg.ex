defmodule Switch.Msg do
  @moduledoc false

  def handle(%{processed: false, type: "switch"} = msg_in) do
    alias Switch.DB.Device
    alias Switch.Notify

    # the with begins with processing the message through DB.Device.upsert/1
    with %{device: switch_device} = msg <- Device.upsert(msg_in),
         # was the upset a success?
         {:ok, %Device{}} <- switch_device,
         # technically the message has been processed at this point
         msg <- put_in(msg.processed, true),
         # send any notifications requested
         msg <- Notify.notify_as_needed(msg) do
      # Switch does not write any data to the timeseries database
      # (unlike Sensor, Remote) so simulate the write_rc success
      put_in(msg, [:write_rc], {:processed, :ok})
    else
      # if there was an error, add fault: <device_fault> to the message and
      # the corresponding <device_fault>: <error> to signal to downstream
      # functions there was an issue
      error ->
        x = %{processed: true, fault: :switch_fault, switch_fault: error}
        Map.merge(msg_in, x)
    end
  end

  # if the primary handle_message does not match then simply return the msg
  # since it wasn't for switch and/or has already been processed in the
  # pipeline
  def handle(%{} = msg_in), do: msg_in
end
