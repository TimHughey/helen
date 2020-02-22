defmodule Thermostat.Control do
  @moduledoc false

  require Logger

  alias Thermostat.Profile

  def current_val(%Thermostat{sensor: sensor}) do
    Sensor.fahrenheit(name: sensor, since_secs: 30)
  end

  # handle the case when a thermostat is disabled
  def next_state(%{}, "disabled", _set_pt, _val), do: "disabled"

  # handle the case where the sensor doesn't have a value
  def next_state(%{}, state, set_pt, val)
      when is_nil(val) or is_nil(set_pt) or state === "stopped",
      do: "off"

  # handle the case when a thermostat is in standby
  def next_state(%{name: "standby"}, _state, _set_pt, _val), do: "off"

  # handle typical operational case of thermostat controlling a device
  def next_state(
        %{low_offset: low_offset, high_offset: high_offset},
        state,
        set_pt,
        val
      ) do
    cond do
      val > set_pt + high_offset and state in ["on", "started", "disabled"] ->
        "off"

      val < set_pt + low_offset and state in ["off", "started", "disabled"] ->
        "on"

      true ->
        # if none of the above then keep the same state
        # this handles the case when the temperature is between the low / high offsets
        state
    end
  end

  # handle invocation with an empty map
  def next_state(%{}, state, set_pt, val) do
    next_state(%{low_offset: 0.0, high_offset: 0.0}, state, set_pt, val)
  end

  def state_to_position("on"), do: true
  def state_to_position(_other), do: false

  def temperature(%Thermostat{name: name, active_profile: profile} = t)
      when is_nil(profile) do
    Thermostat.log?(t) &&
      Logger.warn([
        inspect(name, pretty: true),
        " active profile is ",
        inspect(profile, pretty: true)
      ])

    {:nil_active_profile, t}
  end

  def temperature(%Thermostat{name: name, active_profile: profile} = t)
      when profile == "none" do
    Thermostat.log?(t) &&
      Logger.warn([
        inspect(name, pretty: true),
        " active profile is ",
        inspect(profile, pretty: true)
      ])

    {:no_active_profile, t}
  end

  def temperature(%Thermostat{} = t) do
    profile = Profile.active(t)

    curr_val = current_val(t)
    set_pt = Profile.set_point(profile)

    next_state = next_state(profile, Thermostat.state(t), set_pt, curr_val)

    if next_state === Thermostat.state(t) do
      # handle no change in state
      {:ok, t}
    else
      Switch.position(Thermostat.switch(t),
        position: state_to_position(next_state),
        lazy: true
      )

      Thermostat.state(t, next_state)
    end
  end

  def stop(%Thermostat{} = t) do
    Switch.position(Thermostat.switch(t),
      position: false,
      lazy: true,
      ack: false
    )

    Thermostat.state(t, "off")
  end
end
