defmodule Rena.Sensor.Result do
  alias __MODULE__

  defstruct gt_high: 0, gt_mid: 0, lt_low: 0, lt_mid: 0, invalid: 0, valid: 0, total: 0

  @type zero_or_positive_integer() :: 0 | pos_integer()
  @type t :: %Result{
          gt_high: zero_or_positive_integer(),
          gt_mid: zero_or_positive_integer(),
          lt_low: zero_or_positive_integer(),
          lt_mid: zero_or_positive_integer(),
          invalid: zero_or_positive_integer(),
          valid: zero_or_positive_integer(),
          total: zero_or_positive_integer()
        }

  @known_keys [:gt_high, :gt_mid, :lt_low, :lt_mid]
  def tally_datapoint(check, %Result{} = r) when is_map_key(r, check) do
    case check do
      key when key in @known_keys -> inc_datapoint(r, key) |> inc_valid()
      _ -> inc_invalid(r)
    end
  end

  def tally_total(%Result{} = r), do: %Result{r | total: r.valid + r.invalid}

  defp inc(val), do: val + 1
  defp inc_datapoint(%Result{} = r, dp), do: Map.update!(r, dp, &inc/1)
  defp inc_valid(%Result{} = r), do: Map.update!(r, :valid, &inc/1)
  defp inc_invalid(%Result{} = r), do: Map.update!(r, :invalid, &inc/1)
end

defmodule Rena.Sensor.Range do
  alias __MODULE__
  alias Rena.Sensor.Result

  defstruct low: nil, high: nil, unit: :temp_f

  @type units() :: :temp_f | :temp_c | :relhum
  @type t :: %Range{low: float(), high: float(), unit: units()}

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

defmodule Rena.Sensor do
  alias Rena.Sensor.{Range, Result}

  @type alfred() :: module() | nil
  @type names() :: [String.t()]
  @type compare_opts() :: [{:alfred, module()}]

  @spec range_compare(names(), %Range{}, list()) :: Result.t()
  def range_compare(names, %Range{} = range, opts \\ []) when is_list(opts) do
    alias Alfred.ImmutableStatus, as: Status

    alfred = opts[:alfred] || Alfred

    for name when is_binary(name) <- List.wrap(names), reduce: %Result{} do
      acc ->
        case alfred.status(name) do
          %Status{good?: true, datapoints: dpts} -> Range.compare(dpts, range) |> Result.tally_datapoint(acc)
          _ -> Result.tally_datapoint(:invalid, acc)
        end
    end
    |> Result.tally_total()
  end
end
