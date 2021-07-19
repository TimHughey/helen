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
  alias Alfred.ImmutableStatus, as: ImmStatus
  alias Alfred.MutableStatus, as: MutStatus
  alias Alfred.NotifyMemo, as: Memo
  alias Alfred.NotifyTo
  alias Broom.TrackerEntry
  alias Eva.Equipment
  alias Eva.Follow.{Follower, Leader}
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
  @type value_key() :: atom()
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
    tags = [variant: vf.name, mode: mode]
    Betty.app_error(vf.mod, tags ++ [control: true])

    if vf.equipment.ttl_expired? do
      Betty.app_error(vf.mod, tags ++ [equipment: vf.equipment.name, ttl_expired: true])
    end

    if vf.leader.ttl_expired? do
      Betty.app_error(vf.mod, tags ++ [leader: vf.leader.name, ttl_expired: true])
    end

    if vf.follower.ttl_expired? do
      Betty.app_error(vf.mod, tags ++ [follower: vf.follower.name, ttl_expired: true])
    end

    Logger.info("\n#{inspect(memo, pretty: true)}\n#{inspect(memo, pretty: true)}")

    vf
  end

  def find_devices(%Follow{} = vf) do
    # get a copy of the names to find
    to_find = vf.names.needed

    # clear the needed names.  needed names not found will be accumulated
    vf = %Follow{vf | names: %{vf.names | needed: []}}

    for name <- to_find, reduce: vf do
      %Follow{} = vf ->
        # we want all notifications and to restart when Alfred restarts
        reg_rc = Alfred.notify_register(name, frequency: :all, link: true)

        case reg_rc do
          {:ok, %NotifyTo{} = nt} -> vf |> add_found_name(name) |> add_notify_name(nt)
          _ -> add_needed_name(vf, name)
        end
    end
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

  def mode(%Follow{} = vf, mode) do
    %Follow{vf | mode: mode} |> adjust_mode_as_needed()
  end

  def new(%Follow{} = vf, %Opts{} = opts, extra_opts) do
    x = extra_opts[:cfg]

    %Follow{
      vf
      | name: x[:name],
        mod: opts.server.name,
        leader: Leader.new(x),
        follower: Follower.new(x),
        equipment: Equipment.new(x),
        names: %{needed: [], found: []},
        notifies: %{},
        valid?: true
    }
    |> make_needed_names()
  end

  defp add_found_name(vf, name) do
    %Follow{vf | names: %{vf.names | found: [name] ++ vf.names.found}}
  end

  defp add_needed_name(vf, name) do
    %Follow{vf | names: %{vf.names | needed: [name] ++ vf.names.needed}}
  end

  defp add_notify_name(vf, %NotifyTo{} = nt) do
    %Follow{vf | notifies: put_in(vf.notifies, [nt.ref], nt.name)}
  end

  # (1 of 2) handle standby mode; ensure equipment is off
  defp adjust_mode_as_needed(%Follow{mode: :standby} = vf),
    do: vf.equipment |> Equipment.off() |> update(vf)

  # (2 of 2) no action necessary
  defp adjust_mode_as_needed(vf), do: vf

  defp make_needed_names(vf) do
    needed = [vf.leader.name, vf.follower.name, vf.equipment.name]
    %Follow{vf | names: %{vf.names | needed: needed}}
  end

  # (1 of 3) update equipment
  defp update(%Equipment{} = x, %Follow{} = vf), do: %Follow{vf | equipment: x}
  defp update(%Follower{} = x, %Follow{} = vf), do: %Follow{vf | follower: x}
  defp update(%Leader{} = x, %Follow{} = vf), do: %Follow{vf | leader: x}
end

defimpl Eva.Variant, for: Eva.Follow do
  alias Alfred.NotifyMemo, as: Memo
  alias Broom.TrackerEntry
  alias Eva.{Follow, Opts}

  def control(%Follow{} = vf, %Memo{} = memo, mode), do: Follow.control(vf, memo, mode)
  def current_mode(%Follow{} = vf), do: vf.mode
  def find_devices(%Follow{} = vf), do: Follow.find_devices(vf)
  def found_all_devs?(%Follow{} = v), do: v.names.needed == []
  def handle_notify(%Follow{} = vf, %Memo{} = memo, mode), do: Follow.handle_notify(vf, memo, mode)
  def handle_release(%Follow{} = vf, %TrackerEntry{} = te), do: Follow.handle_release(vf, te)
  def mode(%Follow{} = vf, mode), do: Follow.mode(vf, mode)
  def new(%Follow{} = vf, %Opts{} = opts, extra_opts), do: Follow.new(vf, opts, extra_opts)
  def valid?(%Follow{} = v), do: v.valid?
end
