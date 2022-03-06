defmodule Rena.Sensor do
  @moduledoc false

  @range_keys [:high, :mid, :low, :unit]
  @range_default Enum.into(@range_keys, %{}, &{&1, nil})

  @band_keys [:gt_high, :gt_mid, :lt_mid, :lt_low]
  @tally_keys @band_keys ++ [:invalid, :valid, :total]
  @tally_default Enum.into(@tally_keys, %{}, &{&1, 0})

  @adjust_default [lower: [gt_high: 1], raise: [lt_low: 1], default: :no_change]

  @valid_when_keys [:total, :valid]
  @valid_when_default Enum.into(@valid_when_keys, %{}, &{&1, 0})

  @cmds_default %{raise: "on", lower: "off"}

  defstruct names: [],
            range: @range_default,
            tally: @tally_default,
            adjust_when: @adjust_default,
            valid_when: @valid_when_default,
            cmds: @cmds_default,
            halt_reason: :none,
            next_action: {:no_change, :none},
            reading_at: nil

  @type t :: %__MODULE__{
          names: [String.t(), ...],
          range: map(),
          tally: map(),
          adjust_when: list(),
          valid_when: map(),
          cmds: map(),
          halt_reason: :none | String.t(),
          next_action: tuple(),
          reading_at: DateTime.t()
        }

  def freshen(%__MODULE__{} = sensor, equipment, opts) do
    opts = Keyword.put(opts, :return, :sensor)

    Rena.Sensor.tally(sensor, opts) |> Rena.Sensor.next_action(equipment, opts)
  end

  # New

  @new_keys [:names, :range, :valid_when, :adjust_when, :cmds]
  def new(args) do
    fields_raw = Keyword.take(args, @new_keys)

    Enum.into(fields_raw, [], fn
      {:names = key, <<_::binary>> = val} -> {key, List.wrap(val)}
      {:names = key, x} when is_list(x) -> {key, x}
      {:range = key, opts} -> {key, new_range(opts)}
      # NOTE: adjust_range must be a list; append defaults to ensure on/off at high and low
      {:adjust_when = key, opts} -> {key, new_adjust_when(opts)}
      {key, val} when is_list(val) -> {key, Enum.into(val, %{})}
      {key, %{} = val} -> {key, val}
      kv -> raise("unrecognized arg: #{inspect(kv)}")
    end)
    |> then(&struct(__MODULE__, &1))
  end

  @adjust_base [lower: [], raise: [], default: :no_change]
  def new_adjust_when(opts) do
    Keyword.take(opts, Keyword.keys(@adjust_base))
    |> Enum.reduce(@adjust_base, fn
      # handle :lower and :raise which are list
      {action, kw_list}, acc when is_list(kw_list) ->
        default = Keyword.get(@adjust_default, action)
        put_in(acc, [action], Keyword.merge(default, kw_list))

      # handle the default option
      {action, opt}, acc when is_atom(opt) ->
        put_in(acc, [action], opt)
    end)
  end

  @range_error "must specify [:high, :low, :unit] "
  def new_range(opts) do
    range = Enum.into(opts, %{})

    unless match?(%{high: _, low: _, unit: _}, range), do: raise(@range_error <> inspect(opts))

    put_in(range, [:mid], (range.high - range.low) / 2 + range.low)
  end

  ### Next Action

  defmacro chk_map_put(val, key) do
    quote bind_quoted: [val: val, key: key] do
      chk_map = var!(chk_map)
      put_in(chk_map, [key], val)
    end
  end

  @next_action_steps [:reading_at, :cmd_have, :log_cmd, :action_want, :compare, :finalize]
  @next_action_default {:no_change, :none}
  @next_action_chk_map %{
    cmd_have: nil,
    action_want: :no_change,
    cmd_want: :no_change,
    next_action: @next_action_default,
    halt_reason: :none
  }
  def next_action(%__MODULE__{} = sensor, <<_::binary>> = equipment, opts) do
    {return_val, opts_rest} = Keyword.pop(opts, :return)

    chk_map = Map.put(@next_action_chk_map, :equipment, equipment)

    Enum.reduce(@next_action_steps, chk_map, fn
      :finalize, chk_map -> next_action_finalize(chk_map, return_val, sensor)
      :reading_at, chk_map -> check_reading_at(chk_map, sensor)
      _step, %{halt_reason: <<_::binary>>} = chk_map -> chk_map
      :action_want, chk_map -> action_want(chk_map, sensor)
      :cmd_have, chk_map -> equipment_status(chk_map, opts_rest)
      :log_cmd, chk_map -> log_cmd(chk_map, opts_rest)
      :compare, chk_map -> next_action_compare(chk_map, sensor)
    end)
  end

  @actions [:raise, :lower]
  def action_want(chk_map, %{tally: tally, adjust_when: adjust_when} = _sensor) do
    {default, adjust_when} = Keyword.pop(adjust_when, :default, :no_change)

    Enum.reduce(adjust_when, default, fn
      # action decided, spin through rest of adjust_when
      _, acc when acc in @actions ->
        acc

      # have an action, compare the action opts to the tally counts
      {action, [_ | _] = opts}, acc ->
        want_action? = Enum.any?(opts, fn {key, adjust} -> get_in(tally, [key]) >= adjust end)
        (want_action? && action) || acc
    end)
    |> chk_map_put(:action_want)
  end

  def check_reading_at(chk_map, %{reading_at: reading_at}) do
    case reading_at do
      %DateTime{} -> chk_map
      _ -> chk_map_put("not enough valid sensors", :halt_reason)
    end
  end

  def equipment_status(%{equipment: name} = chk_map, opts) do
    alfred = opts[:alfred] || Alfred

    case alfred.status(name, opts) do
      %{rc: :ok, story: %{cmd: cmd}} -> chk_map_put(cmd, :cmd_have)
      _ -> chk_map_put("invalid status", :halt_reason)
    end
  end

  def log_cmd(%{equipment: equipment, cmd_have: cmd} = chk_map, opts) do
    server_name = opts[:server_name]
    name = opts[:name]

    tags = [equipment: equipment, server_name: server_name, name: name]
    fields = [cmd_have: cmd]

    {:ok, _point} = Betty.runtime_metric(tags, fields)

    chk_map
  end

  @want_fields [:halt_reason, :next_action, :reading_at, :tally]
  def next_action_finalize(chk_map, return_val, sensor) do
    cond do
      return_val == :chk_map -> chk_map
      return_val == :sensor -> struct(sensor, Map.take(chk_map, @want_fields))
      true -> chk_map.next_action
    end
  end

  def next_action_compare(%{action_want: action_want} = chk_map, %{cmds: cmds} = _sensor) do
    cmd_want = Map.get(cmds, action_want, :none)

    cond do
      action_want == :no_change -> {:no_change, :none}
      chk_map.cmd_have == cmd_want -> {:no_change, :none}
      true -> Enum.find(cmds, {:no_match, cmd_want}, &match?({_action, ^cmd_want}, &1))
    end
    |> chk_map_put(:next_action)
  end

  ### Tally

  @tally_steps [:names, :counts, :finalize]
  def tally(%__MODULE__{} = sensor, opts) do
    # NOTE: begin with an empty tally
    tally = @tally_default

    # creates a tally of datapoint bands for all sensor names
    Enum.reduce(@tally_steps, tally, fn
      :names, tally -> names(tally, sensor.names, sensor.range, opts)
      :counts, tally -> counts(tally)
      :finalize, tally -> finalize(tally, sensor, opts)
    end)
  end

  def compare(tally, %{} = range) do
    sensor_val = get_in(tally, [:daps, range.unit])

    cond do
      not is_number(sensor_val) -> :invalid
      sensor_val <= range.low -> :lt_low
      sensor_val >= range.high -> :gt_high
      sensor_val <= range.mid -> :lt_mid
      sensor_val > range.mid -> :gt_mid
    end
    |> then(fn key -> update_in(tally, [key], &(&1 + 1)) end)
  end

  def counts(tally) do
    tally = put_in(tally, [:total], tally.invalid)

    Enum.reduce(@band_keys, tally, fn key, tally ->
      band_count = get_in(tally, [key])

      update_in(tally, [:valid], &(&1 + band_count))
      |> update_in([:total], &(&1 + band_count))
    end)
  end

  def finalize(tally, %{valid_when: valid_when} = sensor, _opts) do
    reading_at = Enum.all?(valid_when, &(tally[elem(&1, 0)] >= elem(&1, 1))) && Timex.now()

    struct(sensor, reading_at: reading_at, tally: tally)
  end

  @name_steps [:status, :compare, :clean]
  def names(tally, names, range, opts) do
    # NOTE: act on all names in this sensor
    Enum.reduce(names, tally, fn name, tally ->
      # NOTE: compute adn record the datapoint band
      Enum.reduce(@name_steps, tally, fn
        :status, tally -> status_sensor(name, tally, opts)
        :compare, tally -> compare(tally, range)
        :clean, tally -> Map.drop(tally, [:daps])
      end)
    end)
  end

  def status_sensor(name, tally, opts) do
    alfred = opts[:alfred] || Alfred

    status = alfred.status(name, opts)

    case status do
      %{rc: :ok, story: daps} -> put_in(tally, [:daps], daps)
      _ -> put_in(tally, [:daps], %{})
    end
  end
end
