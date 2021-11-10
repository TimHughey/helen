defmodule Eva.Setpoint.Leader do
  use Timex
  alias __MODULE__

  defstruct name: nil, datapoint: nil, status: nil, since_ms: 60_000

  @type t :: %Leader{
          name: String.t(),
          datapoint: :temp_c | :temp_f | :relhum,
          status: Alfred.ImmutableStatus.t(),
          since_ms: pos_integer()
        }

  def new(x) do
    sensor = x[:sensor][:leader]
    name = sensor[:name] || "unset leader"
    datapoint = (sensor[:datapoint] || "unset") |> String.to_atom()
    since_ms = sensor[:since] |> Eva.parse_duration()

    %Leader{name: name, datapoint: datapoint}
    |> then(fn x -> if since_ms, do: %Leader{x | since_ms: since_ms} end)
  end

  def update_status(%Leader{} = x) do
    %Leader{x | status: Alfred.status(x.name, since_ms: x.since_ms)}
  end
end

defmodule Eva.Setpoint do
  require Logger

  alias __MODULE__
  alias Alfred.{ExecCmd, ExecResult}
  alias Alfred.ImmutableStatus, as: ImmStatus
  alias Alfred.MutableStatus, as: MutStatus
  alias Alfred.Notify.{Entry, Memo}
  alias Broom.TrackerEntry
  alias Eva.{Equipment, Names, Opts}
  alias Eva.Setpoint.Leader

  defstruct name: nil,
            mod: nil,
            setpoint: nil,
            range: [-1.0, 1.0],
            leader: %Leader{},
            equipment: %Equipment{},
            names: %{needed: [], found: []},
            notifies: %{},
            mode: :init,
            valid?: true

  @type mode() :: :init | :raising | :idle | :lowering | :standby
  @type value_key() :: atom()
  @type t :: %Setpoint{
          name: String.t(),
          mod: module(),
          setpoint: number(),
          range: nonempty_list(),
          leader: Leader.t(),
          equipment: Equipment.t(),
          names: %{needed: list(), found: list()},
          notifies: %{required(reference()) => Entry.t()},
          mode: mode(),
          valid?: boolean()
        }

  # (1 of x) normal operations for equipment that raises the sensor value
  def control(
        %Setpoint{
          setpoint: setpoint,
          range: [low_pt, high_pt],
          leader: %Leader{status: %ImmStatus{good?: true} = leader, datapoint: datapoint},
          equipment:
            %Equipment{impact: :raises, name: equip_name, status: %MutStatus{good?: true}} = equipment
        } = v,
        %Memo{name: memo_name},
        :ready
      )
      when memo_name == equip_name and low_pt < high_pt do
    diff = ImmStatus.diff(datapoint, setpoint, leader) |> Float.round(3)

    cond do
      diff <= low_pt ->
        equipment |> Equipment.on() |> update(v) |> Setpoint.mode(:raising)

      diff >= high_pt ->
        equipment |> Equipment.off() |> update(v) |> Setpoint.mode(:idle)

      diff > low_pt and diff < high_pt ->
        equipment |> Equipment.off() |> update(v) |> Setpoint.mode(:idle)
    end
  end

  # (2 of x) server is in standby mode; ensure equipment is off
  def control(
        %Setpoint{equipment: %Equipment{name: equip_name}} = v,
        %Memo{name: memo_name},
        :standby
      )
      when memo_name == equip_name do
    v.equipment |> Equipment.off() |> update(v) |> mode(:standby)
  end

  # (3 of x) quietly ignore requests to control equipment when notify is for sensors
  def control(%Setpoint{equipment: %Equipment{name: equip_name}} = v, %Memo{name: memo_name}, :ready)
      when equip_name != memo_name,
      do: v

  # (4 of x) quietly ignore requests to control equipment while initializing or in standby
  def control(%Setpoint{mode: vmode} = v, %Memo{}, _mode) when vmode in [:init, :standby], do: v

  # (x of x) an issue exists
  def control(%Setpoint{} = v, %Memo{}, mode) do
    tags = [variant: v.name, mode: mode]
    Betty.app_error(v.mod, tags ++ [control: true])

    if v.equipment.ttl_expired? do
      Betty.app_error(v.mod, tags ++ [equipment: v.equipment.name, ttl_expired: true])
    end

    if v.leader.ttl_expired? do
      Betty.app_error(v.mod, tags ++ [leader: v.leader.name, ttl_expired: true])
    end

    v
  end

  def execute(%Setpoint{} = vs, %ExecCmd{} = _ec, _from) do
    {vs, %ExecResult{}}
  end

  def handle_notify(%Setpoint{} = v, %Memo{} = _momo, :starting), do: v

  def handle_notify(%Setpoint{} = v, %Memo{} = memo, _mode) do
    cond do
      memo.name == v.leader.name ->
        Leader.update_status(v.leader) |> update(v)

      memo.name == v.equipment.name ->
        Equipment.update_status(v.equipment) |> update(v)
    end
  end

  def handle_release(%Setpoint{} = v, %TrackerEntry{} = te) do
    fields = [cmd: te.cmd]
    tags = [module: v.mod, equipment: true, device: v.equipment.name, impact: v.mode]
    Betty.metric("eva", fields, tags)

    te |> Equipment.handle_release(v.equipment) |> update(v)
  end

  def mode(%Setpoint{} = v, mode) do
    %Setpoint{v | mode: mode} |> adjust_mode_as_needed()
  end

  def new(%Opts{} = opts, extra_opts) do
    x = extra_opts[:cfg]

    leader = Leader.new(x)
    equipment = Equipment.new(x)

    default = %Setpoint{}

    %Setpoint{
      name: x[:name],
      mod: opts.server.name,
      setpoint: x[:setpoint],
      range: x[:range] || default.range,
      leader: leader,
      equipment: equipment,
      names: Names.new([leader.name, equipment.name])
    }
  end

  def status(%Setpoint{} = v, _opts) do
    %MutStatus{
      name: v.name,
      good?: v.equipment.status.good?,
      cmd: v.equipment.status.cmd,
      extended: v,
      status_at: DateTime.utc_now()
    }
  end

  # (1 of 2) handle standby mode; ensure equipment is off
  defp adjust_mode_as_needed(%Setpoint{mode: :standby} = v),
    do: v.equipment |> Equipment.off() |> update(v)

  # (2 of 2) no action necessary
  defp adjust_mode_as_needed(v), do: v

  # (1 of 3) update equipment
  defp update(%Equipment{} = x, %Setpoint{} = v), do: %Setpoint{v | equipment: x}
  defp update(%Leader{} = x, %Setpoint{} = v), do: %Setpoint{v | leader: x}
end

defimpl Eva.Variant, for: Eva.Setpoint do
  alias Alfred.ExecCmd
  alias Alfred.Notify.Memo
  alias Broom.TrackerEntry
  alias Eva.Setpoint

  def control(%Setpoint{} = v, %Memo{} = memo, mode), do: Setpoint.control(v, memo, mode)
  def execute(%Setpoint{} = v, %ExecCmd{} = ec, from), do: Setpoint.execute(v, ec, from)
  def handle_instruct(variant, _instruct), do: variant
  def handle_notify(%Setpoint{} = v, %Memo{} = memo, mode), do: Setpoint.handle_notify(v, memo, mode)
  def handle_release(%Setpoint{} = v, %TrackerEntry{} = te), do: Setpoint.handle_release(v, te)
  def status(%Setpoint{} = v, opts), do: Setpoint.status(v, opts)
end
