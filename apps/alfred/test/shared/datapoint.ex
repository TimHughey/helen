defmodule Alfred.Test.Datapoint do
  @moduledoc false

  defstruct temp_c: nil, temp_f: nil, reading_at: nil

  def new(parts, at) when is_map(parts) do
    Map.take(parts, [:temp_f, :temp_c, :relhum])
    |> Enum.into([])
    |> new(at)
  end

  def new(fields, %DateTime{} = at) do
    [{:reading_at, at} | fields]
    |> then(fn fields -> struct(__MODULE__, fields) end)
  end
end
