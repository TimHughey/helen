defmodule Sally.MsgIn.State do
  require Logger

  alias __MODULE__
  alias Sally.MsgIn.Opts

  defstruct opts: %Opts{}

  @type t :: %__MODULE__{opts: Opts.t()}
end
