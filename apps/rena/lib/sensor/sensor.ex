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
