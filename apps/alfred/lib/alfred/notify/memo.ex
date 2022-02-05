defmodule Alfred.Memo do
  @moduledoc """
    Name notification info
  """

  defstruct name: nil, ref: nil, pid: nil, seen_at: nil, missing?: false

  @type t :: %__MODULE__{
          name: String.t(),
          ref: reference(),
          pid: pid(),
          seen_at: DateTime.t(),
          missing?: boolean()
        }

  def new(base_info, overrides) when is_struct(base_info) do
    Map.from_struct(base_info) |> new(overrides)
  end

  def new(base_info, overrides) when is_map(base_info) do
    {at_map, fields_rest} = Map.pop(base_info, :at)
    seen_at = Map.get(at_map, :seen, DateTime.utc_now())

    fields = Map.put(fields_rest, :seen_at, seen_at)
    overrides = Enum.into(overrides, %{})

    struct(__MODULE__, Map.merge(fields, overrides))
  end

  def send(base_info, overrides) do
    memo = new(base_info, overrides)

    Process.send(memo.pid, {Alfred, memo}, [])
  end
end
