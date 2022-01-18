defmodule Rena.Sensor do
  @moduledoc false

  @type alfred() :: module() | nil
  @type names() :: [String.t()]
  @type compare_opts() :: [{:alfred, module()}]

  @spec range_compare(names(), %Rena.Sensor.Range{}, list()) :: Rena.Sensor.Result.t()
  def range_compare(names, %Rena.Sensor.Range{} = range, opts \\ []) when is_list(opts) do
    alfred = opts[:alfred] || Alfred

    List.wrap(names)
    |> Enum.reduce(%Rena.Sensor.Result{}, fn name, acc ->
      status = alfred.status(name, opts)

      case status do
        %Alfred.Status{rc: :ok, detail: dpts} ->
          Rena.Sensor.Range.compare(dpts, range) |> Rena.Sensor.Result.tally_datapoint(acc)

        _error ->
          Rena.Sensor.Result.tally_datapoint(:invalid, acc)
      end
    end)
    |> Rena.Sensor.Result.tally_total()
  end
end
