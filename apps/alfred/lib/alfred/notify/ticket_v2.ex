defmodule Alfred.Ticket do
  @moduledoc false

  defstruct name: nil, ref: nil, notifier_pid: nil, opts: %{}

  @type interval_ms() :: 0 | pos_integer()
  @type missing_ms() :: 0 | pos_integer()
  @type ticket_opts() :: %{ms: %{interval: interval_ms(), missing: missing_ms}, send_missing_msg: boolean()}

  @type t :: %__MODULE__{name: String.t(), ref: reference(), opts: ticket_opts()}

  def new(base_info) when is_struct(base_info), do: Map.from_struct(base_info) |> new()

  @doc false
  def new(base_info) when is_map(base_info) do
    base_info
    |> Map.take([:name, :ref, :opts])
    |> Map.put(:notifier_pid, self())
    |> then(fn fields -> struct(__MODULE__, fields) end)
  end
end
