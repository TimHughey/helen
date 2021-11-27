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
