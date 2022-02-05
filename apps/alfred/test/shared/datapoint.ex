defmodule Alfred.Datapoint do
  @moduledoc false

  defstruct temp_c: nil, temp_f: nil, reading_at: nil

  def new(parts, at) when is_map(parts) do
    Map.take(parts, [:temp_f, :temp_c, :relhum])
    |> Enum.into([])
    |> new(at)
  end

  def new(fields, %DateTime{} = at) do
    struct(__MODULE__, [reading_at: at] ++ fields)
  end
end
