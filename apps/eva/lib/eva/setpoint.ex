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
  alias Alfred.ImmutableStatus, as: ImmStatus
  alias Alfred.MutableStatus, as: MutStatus
  alias Alfred.NotifyMemo, as: Memo
  alias Alfred.NotifyTo
  alias Broom.TrackerEntry
  alias Eva.Equipment
  alias Eva.Opts
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
          notifies: %{required(reference()) => Alfred.NotifyTo.t()},
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
        } = vf,
        %Memo{name: memo_name},
        :ready
      )
      when memo_name == equip_name and low_pt < high_pt do
    diff = ImmStatus.diff(datapoint, setpoint, leader) |> Float.round(3)

    cond do
      diff <= low_pt ->
        equipment |> Equipment.on() |> update(vf) |> Setpoint.mode(:raising)

      diff >= high_pt ->
        equipment |> Equipment.off() |> update(vf) |> Setpoint.mode(:idle)

      diff > low_pt and diff < high_pt ->
        equipment |> Equipment.off() |> update(vf) |> Setpoint.mode(:idle)
    end
  end

  # (2 of x) server is in standby mode; ensure equipment is off
  def control(
        %Setpoint{equipment: %Equipment{name: equip_name}} = vf,
        %Memo{name: memo_name},
        :standby
      )
      when memo_name == equip_name do
    vf.equipment |> Equipment.off() |> update(vf) |> mode(:standby)
  end

  # (3 of x) quietly ignore requests to control equipment when notify is for sensors
  def control(%Setpoint{equipment: %Equipment{name: equip_name}} = vf, %Memo{name: memo_name}, :ready)
      when equip_name != memo_name,
      do: vf

  # (4 of x) quietly ignore requests to control equipment while initializing or in standby
  def control(%Setpoint{mode: vmode} = vf, %Memo{}, _mode) when vmode in [:init, :standby], do: vf

  # (x of x) an issue exists
  def control(%Setpoint{} = vf, %Memo{}, mode) do
    tags = [variant: vf.name, mode: mode]
    Betty.app_error(vf.mod, tags ++ [control: true])

    if vf.equipment.ttl_expired? do
      Betty.app_error(vf.mod, tags ++ [equipment: vf.equipment.name, ttl_expired: true])
    end

    if vf.leader.ttl_expired? do
      Betty.app_error(vf.mod, tags ++ [leader: vf.leader.name, ttl_expired: true])
    end

    vf
  end

  def find_devices(%Setpoint{} = vf) do
    # get a copy of the names to find
    to_find = vf.names.needed

    # clear the needed names.  needed names not found will be accumulated
    vf = %Setpoint{vf | names: %{vf.names | needed: []}}

    for name <- to_find, reduce: vf do
      %Setpoint{} = vf ->
        # we want all notifications and to restart when Alfred restarts
        reg_rc = Alfred.notify_register(name, frequency: :all, link: true)

        case reg_rc do
          {:ok, %NotifyTo{} = nt} -> vf |> add_found_name(name) |> add_notify_name(nt)
          _ -> add_needed_name(vf, name)
        end
    end
  end

  def handle_notify(%Setpoint{} = vf, %Memo{} = _momo, :starting), do: vf

  def handle_notify(%Setpoint{} = vf, %Memo{} = memo, _mode) do
    cond do
      memo.name == vf.leader.name ->
        Leader.update_status(vf.leader) |> update(vf)

      memo.name == vf.equipment.name ->
        Equipment.update_status(vf.equipment) |> update(vf)
    end
  end

  def handle_release(%Setpoint{} = vf, %TrackerEntry{} = te) do
    fields = [cmd: te.cmd]
    tags = [module: vf.mod, equipment: true, device: vf.equipment.name, impact: vf.mode]
    Betty.metric("eva", fields, tags)

    te |> Equipment.handle_release(vf.equipment) |> update(vf)
  end

  def mode(%Setpoint{} = vf, mode) do
    %Setpoint{vf | mode: mode} |> adjust_mode_as_needed()
  end

  def new(%Setpoint{} = vf, %Opts{} = opts, extra_opts) do
    x = extra_opts[:cfg]

    %Setpoint{
      vf
      | name: x[:name],
        mod: opts.server.name,
        setpoint: x[:setpoint],
        range: x[:range] || vf.range,
        leader: Leader.new(x),
        equipment: Equipment.new(x),
        names: %{needed: [], found: []},
        notifies: %{},
        valid?: true
    }
    |> make_needed_names()
  end

  defp add_found_name(vf, name) do
    %Setpoint{vf | names: %{vf.names | found: [name] ++ vf.names.found}}
  end

  defp add_needed_name(vf, name) do
    %Setpoint{vf | names: %{vf.names | needed: [name] ++ vf.names.needed}}
  end

  defp add_notify_name(vf, %NotifyTo{} = nt) do
    %Setpoint{vf | notifies: put_in(vf.notifies, [nt.ref], nt.name)}
  end

  # (1 of 2) handle standby mode; ensure equipment is off
  defp adjust_mode_as_needed(%Setpoint{mode: :standby} = vf),
    do: vf.equipment |> Equipment.off() |> update(vf)

  # (2 of 2) no action necessary
  defp adjust_mode_as_needed(vf), do: vf

  defp make_needed_names(vf) do
    needed = [vf.leader.name, vf.equipment.name]
    %Setpoint{vf | names: %{vf.names | needed: needed}}
  end

  # (1 of 3) update equipment
  defp update(%Equipment{} = x, %Setpoint{} = vf), do: %Setpoint{vf | equipment: x}
  defp update(%Leader{} = x, %Setpoint{} = vf), do: %Setpoint{vf | leader: x}
end

defimpl Eva.Variant, for: Eva.Setpoint do
  alias Alfred.NotifyMemo, as: Memo
  alias Broom.TrackerEntry
  alias Eva.{Setpoint, Opts}

  def control(%Setpoint{} = vf, %Memo{} = memo, mode), do: Setpoint.control(vf, memo, mode)
  def current_mode(%Setpoint{} = vf), do: vf.mode
  def find_devices(%Setpoint{} = vf), do: Setpoint.find_devices(vf)
  def found_all_devs?(%Setpoint{} = v), do: v.names.needed == []
  def handle_notify(%Setpoint{} = vf, %Memo{} = memo, mode), do: Setpoint.handle_notify(vf, memo, mode)
  def handle_release(%Setpoint{} = vf, %TrackerEntry{} = te), do: Setpoint.handle_release(vf, te)
  def mode(%Setpoint{} = vf, mode), do: Setpoint.mode(vf, mode)
  def new(%Setpoint{} = vf, %Opts{} = opts, extra_opts), do: Setpoint.new(vf, opts, extra_opts)
  def valid?(%Setpoint{} = v), do: v.valid?
end
