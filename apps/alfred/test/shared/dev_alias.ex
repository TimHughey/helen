defmodule Alfred.DevAlias do
  @moduledoc false

  use Alfred, name: [backend: :module], execute: []

  defstruct name: "",
            pio: 0,
            description: "<none>",
            ttl_ms: 15_000,
            nature: nil,
            cmds: nil,
            datapoints: nil,
            status: nil,
            register: nil,
            seen_at: nil,
            parts: nil,
            inserted_at: nil,
            updated_at: nil

  @type t :: %__MODULE__{
          name: String.t(),
          pio: pos_integer(),
          description: String.t(),
          ttl_ms: pos_integer(),
          nature: :cmds | :datapoints,
          cmds: list | [],
          datapoints: list | [],
          status: Alfred.Status.t() | nil,
          register: pid | nil,
          seen_at: DateTime.t(),
          parts: map | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @tz "America/New_York"

  # Callbacks

  @impl true
  def execute_cmd(%Alfred.DevAlias{} = dev_alias, opts) do
    new_cmd = Alfred.Command.execute(dev_alias, opts)

    rc = if(new_cmd.acked, do: :ok, else: :busy)

    {rc, new_cmd}
  end

  @impl true
  def status_lookup(%{name: name, nature: :datapoints}, _invoke_args) do
    dev_alias = Alfred.NamesAid.binary_to_parts(name) |> new(register: false)

    %{datapoints: [dap]} = dev_alias

    refined_dap = Map.drop(dap, [:__meta__, :__struct__])

    struct(dev_alias, datapoints: [refined_dap])
  end

  @impl true
  def status_lookup(%{name: name, nature: :cmds}, _invoke_args) do
    Alfred.NamesAid.binary_to_parts(name) |> new(register: false)
  end

  # (2 of 4) construct a new DevAlias from a parts map
  @steps [:nature, :description, :ttl, :tstamps, :cmds, :daps, :struct, :register]
  def new(%{name: name} = parts, opts) when is_list(opts) do
    base_fields = [name: name, parts: parts, pio: 0]

    Enum.reduce(@steps, base_fields, fn
      :nature, fields -> nature(parts, fields)
      :description, fields -> description(parts, fields)
      :ttl, fields -> ttl(parts, fields)
      :tstamps, fields -> timestamps(fields)
      :cmds, fields -> cmds(parts, fields, opts)
      :daps, fields -> datapoints(parts, fields)
      :struct, fields -> struct(__MODULE__, fields)
      :register, dev_alias -> register(dev_alias, opts)
    end)
  end

  def new(<<_::binary>> = name, opts) do
    Alfred.NamesAid.binary_to_parts(name) |> new(opts)
  end

  def ttl_reset(%Alfred.DevAlias{} = dev_alias) do
    struct(dev_alias, updated_at: now(), seen_at: now())
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  def cmds(parts, fields, opts) do
    case parts do
      %{type: :mut} ->
        at = fields[:updated_at]
        cmd = Alfred.Command.new(parts, at, opts)
        [cmds: [cmd], status: cmd]

      _ ->
        []
    end
    |> then(fn cmd_fields -> cmd_fields ++ fields end)
  end

  def datapoints(parts, fields) do
    case parts do
      %{type: :imm} ->
        dap = Alfred.Datapoint.new(parts, fields[:updated_at])
        [datapoints: [dap], status: dap]

      _ ->
        []
    end
    |> then(fn dap_fields -> dap_fields ++ fields end)
  end

  def description(parts, fields) do
    case parts do
      %{type: :imm} -> "sensor"
      %{type: :mut} -> "equipment"
    end
    |> then(fn description -> [description: description] ++ fields end)
  end

  def nature(parts, fields) do
    case parts do
      %{type: :mut} -> :cmds
      %{type: :imm} -> :datapoints
    end
    |> then(fn nature -> [nature: nature] ++ fields end)
  end

  def now, do: Timex.now(@tz)

  def timestamps(fields) do
    # NOTE: __shift_ms__ is a positive value
    update = Timex.shift(now(), milliseconds: fields[:__shift_ms__])
    insert = Timex.shift(update, microseconds: -102)

    [inserted_at: insert, seen_at: update, updated_at: update] ++ fields
  end

  def ttl(parts, fields) do
    case parts do
      %{rc: :ok} -> {5_000, 0}
      %{rc: :expired, expired_ms: ms} -> {ms, (ms + 100) * -1}
      %{rc: :expired} -> {10, -110}
      %{rc: :busy} -> {5_000, -100}
      %{rc: :timeout} -> {5_001, -1000}
      _ -> {13, 0}
    end
    |> then(fn {ttl, shift_ms} -> [ttl_ms: ttl, __shift_ms__: shift_ms] ++ fields end)
  end
end
