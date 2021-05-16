defmodule SensorSim.Datapoint do
  defstruct temp_c: nil, relhum: nil

  @type t :: %__MODULE__{temp_c: float(), relhum: float()}

  alias SensorSim.Datapoint

  def default, do: random(:temp_c)

  # (1 of 3) no datapoint specified, use the default
  def create(nil), do: create(:relhum)

  # (2 of 3) a random datapoint is requested, create it
  def create(kind) when kind in [:temp_c, :relhum] do
    random(kind)
  end

  # (3 of 3) passed a raw map, make a Datapoint from it
  def create(dp) when is_map(dp) do
    case dp do
      %{temp_c: tc, relhum: rh} -> %Datapoint{temp_c: tc, relhum: rh}
      %{temp_c: tc} -> %Datapoint{temp_c: tc}
    end
  end

  # create a list of maps representing valid Datapoints
  # when no valid Datapoints an empty list is returned
  def pruned(%Datapoint{} = dp) do
    case dp do
      %Datapoint{relhum: x} when is_float(x) -> %{temp_c: dp.temp_c, relhum: x}
      %Datapoint{temp_c: x} when is_float(x) -> %{temp_c: x}
      _ -> []
    end
    |> List.wrap()
    |> List.flatten()
  end

  defp random(kind) do
    case kind do
      :temp_c -> %Datapoint{temp_c: random_float(20, 3)}
      :relhum -> %Datapoint{temp_c: random_float(20, 3), relhum: random_float(50, 15)}
    end
  end

  defp random_float(min, spread) do
    base = :rand.uniform(min) * 1.0
    spread = :rand.uniform(spread) * 1.0
    decimal = :rand.uniform(100) * 1.0

    val = base + spread + decimal / 100.0
    Float.round(val, 3)
  end
end
