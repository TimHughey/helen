defmodule PulseWidth.Duty do
  @moduledoc false

  # (1 of 6) duty was not in the original opts
  def calculate(_, nil), do: nil

  # (2 of 6) handle simple duty values
  def calculate(%_{duty_max: max, duty_min: min}, duty)
      when is_integer(duty) and duty >= min and duty <= max,
      do: duty

  # (3 of 6) prevent duty greater than max
  def calculate(%_{duty_max: max}, duty) when duty > max, do: max

  # (4 of 6) prevent duty greater than max
  def calculate(%_{duty_min: min}, duty) when duty < min, do: min

  # (5 of 6) floats less than one are considered percentages
  def calculate(%_{duty_max: max}, duty) when is_float(duty) and duty < 1.0,
    do: percent(duty, max)

  # (6 of 6) floats greater than one become integers
  def calculate(%_{} = dev, duty) when is_float(duty) and duty >= 1.0,
    do: calculate(dev, round(duty))

  def percent(x, max), do: round(x * max)
end
