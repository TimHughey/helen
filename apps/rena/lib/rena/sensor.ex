defmodule Rena.Sensor do
  @moduledoc false

  @range_keys [:high, :mid, :low, :unit]
  @range_default Enum.into(@range_keys, %{}, &{&1, nil})

  @band_keys [:gt_high, :gt_mid, :lt_mid, :lt_low]
  @tally_keys @band_keys ++ [:invalid, :valid, :total]
  @tally_default Enum.into(@tally_keys, %{}, &{&1, 0})

  @valid_when_keys [:total, :valid]
  @valid_when_default Enum.into(@valid_when_keys, %{}, &{&1, 0})

  @cmds_default %{raise: "on", lower: "off"}

  defstruct names: [],
            range: @range_default,
            tally: @tally_default,
            valid_when: @valid_when_default,
            cmds: @cmds_default,
            halt_reason: :none,
            next_action: {:no_change, :none},
            reading_at: nil

  @type t :: %__MODULE__{
          names: [String.t(), ...],
          range: map(),
          tally: map(),
          valid_when: map(),
          cmds: map(),
          halt_reason: :none | String.t(),
          next_action: tuple(),
          reading_at: DateTime.t()
        }

  @new_keys [:names, :range, :valid_when, :cmds]
  def new(args) do
    fields_raw = Keyword.take(args, @new_keys)

    Enum.into(fields_raw, [], fn
      {:names = key, <<_::binary>> = val} -> {key, List.wrap(val)}
      {:names = key, x} when is_list(x) -> {key, x}
      {:range = key, opts} -> {key, new_range(opts)}
      {key, val} when is_list(val) -> {key, Enum.into(val, %{})}
      {key, %{} = val} -> {key, val}
      kv -> raise("unrecognized arg: #{inspect(kv)}")
    end)
    |> then(&struct(__MODULE__, &1))
  end

  @range_error "must specify [:high, :low, :unit] "
  def new_range(opts) do
    range = Enum.into(opts, %{})

    unless match?(%{high: _, low: _, unit: _}, range), do: raise(@range_error <> inspect(opts))

    put_in(range, [:mid], (range.high - range.low) / 2 + range.low)
  end

  ###
  ### Next Action
  ###

  defmacro chk_map_put(val, key) do
    quote bind_quoted: [val: val, key: key] do
      chk_map = var!(chk_map)
      put_in(chk_map, [key], val)
    end
  end

  @next_action_steps [:reading_at, :cmd_have, :cmd_want, :compare, :finalize]
  @na_default {:no_change, :none}
  @na_chk_map %{cmd_have: nil, cmd_want: :no_change, next_action: @na_default, halt_reason: :none}
  def next_action(<<_::binary>> = equipment, %__MODULE__{} = sensor, opts) do
    {return_val, opts_rest} = Keyword.pop(opts, :return)

    chk_map = Map.put(@na_chk_map, :equipment, equipment)

    Enum.reduce(@next_action_steps, chk_map, fn
      :finalize, chk_map when return_val == :chk_map -> chk_map
      :finalize, chk_map when return_val == :sensor -> sensor_from_chk_map(chk_map, sensor)
      :finalize, %{next_action: next_action} -> next_action
      :reading_at, chk_map -> check_reading_at(chk_map, sensor)
      _step, %{halt_reason: <<_::binary>>} = chk_map -> chk_map
      :cmd_have, chk_map -> status_equipment(chk_map, opts_rest)
      :cmd_want, chk_map -> cmd_want(chk_map, sensor)
      :compare, chk_map -> next_action_compare(chk_map, sensor)
    end)
  end

  def action_for_cmd(want_cmd, cmds) do
    Enum.find(cmds, &match?({_action, ^want_cmd}, &1))
  end

  def check_reading_at(chk_map, %{reading_at: reading_at}) do
    case reading_at do
      %DateTime{} -> chk_map
      _ -> chk_map_put("invalid equipment sensor", :halt_reason)
    end
  end

  def cmd_want(chk_map, %{cmds: cmds, tally: tally}) do
    case tally do
      %{gt_high: x} when x >= 1 -> cmds.lower
      %{lt_low: x} when x >= 1 -> cmds.raise
      %{lt_mid: x} when x >= 1 -> cmds.raise
      _ -> :no_change
    end
    |> chk_map_put(:cmd_want)
  end

  def next_action_compare(chk_map, %{cmds: cmds} = _sensor) do
    case chk_map do
      %{cmd_have: cmd, cmd_want: cmd} -> {:no_change, :none}
      %{cmd_want: cmd} -> action_for_cmd(cmd, cmds)
    end
    |> chk_map_put(:next_action)
  end

  @want_fields [:halt_reason, :next_action, :reading_at, :tally]
  def sensor_from_chk_map(chk_map, %__MODULE__{} = sensor) do
    fields = Map.take(chk_map, @want_fields)
    struct(sensor, fields)
  end

  def status_equipment(%{equipment: name} = chk_map, opts) do
    alfred = opts[:alfred] || Alfred

    case alfred.status(name, opts) do
      %{rc: :ok, story: %{cmd: cmd}} -> chk_map_put(cmd, :cmd_have)
      _ -> chk_map_put("invalid status", :halt_reason)
    end
  end

  ###
  ### Tally
  ###

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

  def finalize(tally, %{valid_when: valid_when} = sensor, opts) do
    tz = opts[:timezone] || "Etc/UTC"

    reading_at = Enum.all?(valid_when, &(tally[elem(&1, 0)] >= elem(&1, 1))) && Timex.now(tz)

    fields = [reading_at: if(match?(%DateTime{}, reading_at), do: reading_at, else: nil), tally: tally]
    struct(sensor, fields)
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
