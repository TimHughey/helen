defmodule Sally.MsgOut.State do
  require Logger

  alias __MODULE__
  alias Sally.MsgOut.Opts

  defstruct last_pub: nil, opts: %Opts{}

  @type pub_elapsed_us() :: pos_integer()
  @type last_pub() :: {pub_elapsed_us(), {:ok, reference()}} | {pub_elapsed_us(), :ok}

  @type t :: %__MODULE__{last_pub: last_pub(), opts: Opts.t()}

  def save_last_pub(x, %State{} = s), do: %State{s | last_pub: x}
end
