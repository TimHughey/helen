defmodule Rena.Sensor.Range do
  alias __MODULE__

  defstruct low: nil, high: nil, unit: :temp_f

  @type units() :: :temp_f | :temp_c | :relhum
  @type t :: %Range{low: float(), high: float(), unit: units()}

  def new(opts) do
    case opts do
      x when is_list(x) -> struct(Range, opts)
      x when is_nil(x) -> %Range{}
      x when is_struct(x) -> x
    end
  end

  def compare(dpts, %Range{low: lpt, high: hpt, unit: unit})
      when is_number(lpt) and is_number(hpt) and hpt >= lpt do
    mid_pt = (hpt - lpt) / 2.0 + lpt
    sensor_val = dpts[unit]

    cond do
      is_number(sensor_val) == false -> :invalid
      sensor_val <= lpt -> :lt_low
      sensor_val >= hpt -> :gt_high
      sensor_val <= mid_pt -> :lt_mid
      sensor_val > mid_pt -> :gt_mid
    end
  end

  def compare(_dpts, _range), do: :invalid
end
