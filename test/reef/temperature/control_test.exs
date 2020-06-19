defmodule ReefTemperatureControlTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use Timex

  alias Reef.Temp.Control

  setup do
    :ok
  end

  setup _context do
    opts = [
      sensor: [
        name: "sensor",
        notify_interval: [minutes: 2],
        since: [seconds: 30]
      ],
      switch: [name: "switch", notify_interval: [minutes: 2]]
    ]

    {:ok, state, {:continue, :bootstrap}} = Control.init(opts)

    {:ok, %{default_opts: opts, state: state}}
  end

  @moduletag :reef_temperature_control
  setup_all do
    # test aliases are setup for each test individually
    :ok
  end

  test "init/1 detects missing opts" do
    res = Control.init([])

    assert res == :ignore
  end

  test "init/1 creates the correct initial state" do
    opts = [
      sensor: [
        name: "sensor",
        notify_interval: [minutes: 2],
        since: [seconds: 30]
      ],
      switch: [name: "switch", notify_interval: [minutes: 2]]
    ]

    {:ok, state, {:continue, :bootstrap}} = Control.init(opts)

    assert state[:opts][:sensor][:name]
    assert state[:opts][:switch][:name]
  end

  test "handle_info/2 updates state", context do
    assert {:noreply, new_state, _} =
             Control.handle_info(:timeout, context[:state])

    assert new_state[:timeouts] > 1
    assert Timex.diff(new_state[:last_timeout], ~U[1970-01-01 00:00:00Z])
  end
end
