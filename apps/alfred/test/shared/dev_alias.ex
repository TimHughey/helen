defmodule Alfred.Test.DevAlias do
  @moduledoc false

  use Alfred.Status
  use Alfred.Execute, broom: Alfred.Test.Command
  use Alfred.JustSaw

  defstruct name: "",
            pio: 0,
            description: "<none>",
            ttl_ms: 15_000,
            device: [],
            cmds: nil,
            datapoints: nil,
            inserted_at: nil,
            updated_at: nil

  @tz "America/New_York"

  @impl true
  def execute_cmd(%Alfred.Status{} = status, opts) do
    Alfred.Status.raw(status) |> Alfred.Test.Command.add(opts)
  end

  # (1 of 4) handle unkonwn names
  def new(%{type: :unk}), do: new(nil)

  # (2 of 4) construct a new DevAlias from a parts map
  def new(parts) when is_map(parts) do
    populate_order = [:name, :timestamps, :cmds, :datapoints]

    Enum.reduce(populate_order, [pio: 0], fn
      :name, fields -> [{:name, Map.get(parts, :name)} | fields]
      :timestamps, fields -> timestamps_and_ttl(parts, fields)
      :cmds, fields -> cmds(parts, fields)
      :datapoints, fields -> datapoints(parts, fields)
    end)
    |> new()
  end

  # (3 of 4) construct a DevAlias struct from a list of fields
  def new(fields) when is_list(fields), do: struct(__MODULE__, fields)

  # (3 of 4) catch all
  def new(_), do: nil

  @impl true
  def status_lookup(%{name: name, nature: :datapoints}, opts) when is_list(opts) do
    %{datapoints: [datapoint]} = dev_alias = Alfred.NamesAid.binary_to_parts(name) |> new()

    datapoint
    |> Map.from_struct()
    |> Enum.reject(fn {_key, val} -> is_nil(val) end)
    |> Enum.into(%{})
    |> then(fn datapoint -> struct(dev_alias, datapoints: [datapoint]) end)
  end

  def status_lookup(%{name: name, nature: :cmds}, opts) when is_list(opts) do
    Alfred.NamesAid.binary_to_parts(name) |> new()
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defp cmds(%{type: :mut} = parts, fields) do
    at = fields[:updated_at]
    cmd = Alfred.Test.Command.new(parts, at)

    [{:cmds, List.wrap(cmd)} | fields]
    |> description("equipment")
  end

  defp cmds(_parts, fields), do: fields

  defp datapoints(%{type: :imm} = parts, fields) when is_map(parts) and is_list(fields) do
    at = fields[:updated_at]
    datapoint = Alfred.Test.Datapoint.new(parts, at)

    [{:datapoints, List.wrap(datapoint)} | fields]
    |> description("sensor")
  end

  defp datapoints(_parts, fields), do: fields

  defp description(fields, description), do: [{:description, description} | fields]

  defp now, do: Timex.now(@tz)

  defp timestamps_and_ttl(parts, fields) do
    case parts do
      %{rc: :ok} -> {5_000, 0}
      %{rc: :expired, expired_ms: ms} -> {ms, (ms + 100) * -1}
      %{rc: :pending} -> {5_000, -100}
      %{rc: :orphaned} -> {5_000, -1000}
    end
    |> then(fn {ttl_ms, ms} -> [{:ttl_ms, ttl_ms} | timestamps(fields, ms)] end)
  end

  defp timestamps(fields, ms) do
    # pop the existing keys; the new values will be put back
    {updated_at, fields_rest} = Keyword.pop(fields, :updated_at, now())
    {_inserted_at, fields_rest} = Keyword.pop(fields_rest, :inserted_at)

    # NOTE: ms is a positive value
    updated_at = Timex.shift(updated_at, milliseconds: ms)
    inserted_at = Timex.shift(updated_at, microseconds: -102)

    # put the revised keys into fields
    [{:updated_at, updated_at} | [{:inserted_at, inserted_at} | fields_rest]]
  end
end
