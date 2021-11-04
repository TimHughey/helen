defmodule Rena.Sensor.Result do
  alias __MODULE__

  defstruct gt_high: false, gt_mid: false, lt_low: false, lt_mid: false, invalid: 0, valid: 0

  @type t :: %Result{
          gt_high: boolean(),
          gt_mid: boolean(),
          lt_low: boolean(),
          lt_mid: boolean(),
          invalid: 0 | pos_integer(),
          valid: 0 | pos_integer()
        }

  @known_keys [:gt_high, :gt_mid, :lt_low, :lt_mid]
  def summarize(check, %Result{} = r) when is_map_key(r, check) do
    case check do
      key when key in @known_keys -> %Result{r | valid: r.valid + 1} |> Map.put(key, true)
      _ -> %Result{r | invalid: r.invalid + 1}
    end
  end
end

defmodule Rena.Sensor.Range do
  alias __MODULE__
  alias Rena.Sensor.Result

  defstruct low: nil, high: nil, unit: :temp_f

  @type units() :: :temp_f | :temp_c | :relhum
  @type t :: %Range{low: float(), high: float(), unit: units()}

  def check(dpts, %Range{low: lpt, high: hpt, unit: unit})
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

  def check(_dpts, _range), do: :invalid
end

defmodule Rena.Sensor do
  alias Rena.Sensor.{Range, Result}

  @type alfred() :: module() | nil
  @type names() :: [String.t()]
  @type check_opts() :: [{:alfred, module()}]

  @spec range_compare(names(), %Range{}, list()) :: Result.t()
  def range_compare(names, %Range{} = range, opts \\ []) when is_list(opts) do
    alias Alfred.ImmutableStatus, as: Status

    alfred = opts[:alfred] || Alfred

    for name when is_binary(name) <- List.wrap(names), reduce: %Result{} do
      acc ->
        case alfred.status(name) do
          %Status{good?: true, datapoints: dpts} -> Range.check(dpts, range) |> Result.summarize(acc)
          _ -> Result.summarize(:invalid, acc)
        end
    end
  end
end
