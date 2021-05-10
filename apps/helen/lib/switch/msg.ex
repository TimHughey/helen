defmodule Switch.Msg do
  @moduledoc false

  alias Switch.DB.Device
  alias Switch.{Notify, States}

  @fault_key __MODULE__

  # (1 of 2) nominal case
  def handle(%{processed: false, type: "switch"} = msg_in) do
    res = Repo.transaction(fn -> wrapped(msg_in) end, [])

    case res do
      {:ok, msg_out} -> msg_out
      {:failed, error} -> put_processed_error(msg_in, inspect(error, pretty: true))
    end
  end

  # (2 of 2) if the primary handle_message does not match then simply return the msg
  # since it wasn't for switch and/or has already been processed in the
  # pipeline
  def handle(%{} = msg_in), do: msg_in

  def put_processed_error(msg, error) do
    put_in(msg.processed, true)
    |> put_in([:fault], @fault_key)
    |> put_in([@fault_key], error)
  end

  def validate_success(msg) do
    validate_keys = [:device, :states_rc, :cmd_rc]

    valid? = fn x ->
      Enum.all?(x, fn
        {_key, []} -> true
        {_key, {rc, _}} when rc == :ok -> true
      end)
    end

    if Map.take(msg, validate_keys) |> valid?.() do
      put_in(msg.processed, true)
    else
      put_processed_error(msg, ":device, :states_rc or :cmd_rc failed validation")
    end
  end

  def wrapped(msg_in) do
    msg_in
    |> Device.upsert()
    |> States.incoming_states()
    |> Notify.notify_as_needed()
    |> validate_success()
  end
end
