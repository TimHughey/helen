defmodule Sally.MsgIn.State do
  require Logger

  alias Sally.MsgIn.Opts

  defstruct opts: %Opts{}

  @type t :: %__MODULE__{opts: Opts.t()}
end
