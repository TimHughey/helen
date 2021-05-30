defmodule Sally.MsgIn do
  defstruct payload: nil, topic: nil, host: nil, msg_recv_at: nil

  @type payload :: :unpacked | String.t()

  @type t :: %__MODULE__{payload: payload, topic: String.t(), host: String.t(), msg_recv_at: %DateTime{}}
end
