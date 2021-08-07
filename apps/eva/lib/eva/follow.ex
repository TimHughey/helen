defmodule Eva.Follow.Follower do
  alias __MODULE__

  defstruct name: nil, range: [-1.0, 1.0], status: nil, since_ms: 60_000

  @type t :: %Follower{
          name: String.t(),
          range: list(),
          status: Alfred.ImmutableStatus.t(),
          since_ms: pos_integer()
        }

  def new(x) do
    sensor = x[:sensor][:follower]
    name = sensor[:name] || "unset follower"
    range = sensor[:range]
    since_ms = sensor[:since] |> Eva.parse_duration()

    %Follower{name: name}
    |> then(fn x -> if is_list(range) and length(range) == 2, do: %Follower{x | range: range} end)
    |> then(fn x -> if since_ms, do: %Follower{x | since_ms: since_ms} end)
  end

  def update_status(%Follower{} = x) do
    %Follower{x | status: Alfred.status(x.name, since_ms: x.since_ms)}
  end
end

defmodule Eva.Follow.Leader do
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

defmodule Eva.Follow do
  require Logger

  alias __MODULE__
  alias Alfred.{ExecCmd, ExecResult}
  alias Alfred.ImmutableStatus, as: ImmStatus
  alias Alfred.MutableStatus, as: MutStatus
  alias Alfred.NotifyMemo, as: Memo
  alias Broom.TrackerEntry
  alias Eva.Equipment
  alias Eva.Follow.{Follower, Leader}
  alias Eva.Names
  alias Eva.Opts

  defstruct name: nil,
            mod: nil,
            leader: %Leader{},
            follower: %Follower{},
            equipment: %Equipment{},
            names: %{needed: [], found: []},
            notifies: %{},
            mode: :init,
            valid?: true

  @type mode() :: :init | :raising | :idle | :lowering | :standby
  @type t :: %Follow{
          name: String.t(),
          mod: module(),
          leader: Leader.t(),
          follower: Follower.t(),
          equipment: Equipment.t(),
          names: %{needed: list(), found: list()},
          notifies: %{required(reference()) => Alfred.NotifyTo.t()},
          mode: mode(),
          valid?: boolean()
        }

  # (1 of x) normal operations for equipment that raises the sensor value
  def control(
        %Follow{
          leader: %Leader{status: %ImmStatus{good?: true} = leader, datapoint: datapoint},
          follower: %Follower{status: %ImmStatus{good?: true} = follower, range: [low_pt, high_pt]},
          equipment:
            %Equipment{impact: :raises, name: equip_name, status: %MutStatus{good?: true}} = equipment
        } = vf,
        %Memo{name: memo_name},
        :ready
      )
      when memo_name == equip_name and low_pt < high_pt do
    diff = ImmStatus.diff(datapoint, follower, leader) |> Float.round(3)

    cond do
      diff <= low_pt ->
        equipment |> Equipment.on() |> update(vf) |> Follow.mode(:raising)

      diff >= high_pt ->
        equipment |> Equipment.off() |> update(vf) |> Follow.mode(:idle)

      diff > low_pt and diff < high_pt ->
        equipment |> Equipment.off() |> update(vf) |> Follow.mode(:idle)
    end
  end

  # (2 of x) server is in standby mode; ensure equipment is off
  def control(
        %Follow{equipment: %Equipment{name: equip_name}} = vf,
        %Memo{name: memo_name},
        :standby
      )
      when memo_name == equip_name do
    vf.equipment |> Equipment.off() |> update(vf) |> mode(:standby)
  end

  # (3 of x) quietly ignore requests to control equipment when notify is for sensors
  def control(%Follow{equipment: %Equipment{name: equip_name}} = vf, %Memo{name: memo_name}, :ready)
      when equip_name != memo_name,
      do: vf

  # (4 of x) quietly ignore requests to control equipment while initializing or in standby
  def control(%Follow{mode: vmode} = vf, %Memo{}, _mode) when vmode in [:init, :standby], do: vf

  # (x of x) an issue exists
  def control(%Follow{} = vf, %Memo{} = memo, mode) do
    alias Alfred.ImmutableStatus, as: ImmStatus
    alias Alfred.MutableStatus, as: MutStatus

    tags = [variant: vf.name, mode: mode]
    Betty.app_error(vf.mod, tags ++ [control: true])

    Logger.debug("\n#{inspect(memo, pretty: true)}\n#{inspect(memo, pretty: true)}")

    if vf.equipment.status |> MutStatus.ttl_expired?() do
      Betty.app_error(vf.mod, tags ++ [equipment: vf.equipment.name, ttl_expired: true])
    end

    if vf.leader.status |> ImmStatus.ttl_expired?() do
      Betty.app_error(vf.mod, tags ++ [leader: vf.leader.name, ttl_expired: true])
    end

    if vf.follower.status |> ImmStatus.ttl_expired?() do
      Betty.app_error(vf.mod, tags ++ [follower: vf.follower.name, ttl_expired: true])
    end

    vf
  end

  def execute(%Follow{} = vf, %ExecCmd{cmd: cmd} = ec, _from) when cmd in ["on", "off"] do
    {vf, ExecResult.from_cmd(ec, rc: :unsupported)}
  end

  def handle_notify(%Follow{} = vf, %Memo{} = _momo, :starting), do: vf

  def handle_notify(%Follow{} = vf, %Memo{} = memo, _mode) do
    cond do
      memo.name == vf.leader.name ->
        Leader.update_status(vf.leader) |> update(vf)

      memo.name == vf.follower.name ->
        Follower.update_status(vf.follower) |> update(vf)

      memo.name == vf.equipment.name ->
        Equipment.update_status(vf.equipment) |> update(vf)
    end
  end

  def handle_release(%Follow{} = vf, %TrackerEntry{} = te) do
    fields = [cmd: te.cmd]
    tags = [module: vf.mod, equipment: true, device: vf.equipment.name, impact: vf.mode]
    Betty.metric("eva", fields, tags)

    te |> Equipment.handle_release(vf.equipment) |> update(vf)
  end

  def mode(%Follow{mode: prev_mode} = vf, mode) do
    vf = %Follow{vf | mode: mode}
    fake_memo = %Memo{name: vf.equipment.name}

    case {vf, mode} do
      {vf, mode} when mode == prev_mode -> vf
      {vf, :resume} -> vf |> control(fake_memo, :ready)
      {vf, :standby} -> vf |> control(fake_memo, :standby)
      {vf, _mode} -> vf
    end
  end

  def new(%Opts{} = opts, extra_opts) do
    cfg = extra_opts[:cfg]

    leader = Leader.new(cfg)
    follower = Follower.new(cfg)
    equipment = Equipment.new(cfg)

    %Follow{
      name: cfg[:name],
      mod: opts.server.name,
      leader: leader,
      follower: follower,
      equipment: equipment,
      names: Names.new([leader.name, follower.name, equipment.name])
    }
  end

  def status(%Follow{} = vf, _opts) do
    %MutStatus{
      name: vf.name,
      good?: vf.equipment.status.good?,
      cmd: vf.equipment.status.cmd,
      extended: vf,
      status_at: DateTime.utc_now()
    }
  end

  # (1 of 3) update equipment
  defp update(%Equipment{} = x, %Follow{} = vf), do: %Follow{vf | equipment: x}
  defp update(%Follower{} = x, %Follow{} = vf), do: %Follow{vf | follower: x}
  defp update(%Leader{} = x, %Follow{} = vf), do: %Follow{vf | leader: x}
end

defimpl Eva.Variant, for: Eva.Follow do
  alias Alfred.ExecCmd
  alias Alfred.NotifyMemo, as: Memo
  alias Broom.TrackerEntry
  alias Eva.Follow

  def control(%Follow{} = vf, %Memo{} = memo, mode), do: Follow.control(vf, memo, mode)
  def execute(%Follow{} = vf, %ExecCmd{} = ec, from), do: Follow.execute(vf, ec, from)
  def handle_instruct(variant, _instruct), do: variant
  def handle_notify(%Follow{} = vf, %Memo{} = memo, mode), do: Follow.handle_notify(vf, memo, mode)
  def handle_release(%Follow{} = vf, %TrackerEntry{} = te), do: Follow.handle_release(vf, te)
  def status(%Follow{} = vf, opts), do: Follow.status(vf, opts)
end
