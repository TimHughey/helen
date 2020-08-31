defmodule HelenWorkersTest do
  @moduledoc false

  use Timex
  use ExUnit.Case

  alias Helen.Workers

  test "can find module for a pwm simple device?" do
    res = Workers.module(:front_leds, "front leds evergreen")

    assert PulseWidth.exists?("front leds evergreen")
    assert get_in(res, [:found?])
    assert get_in(res, [:name]) == "front leds evergreen"
  end

  test "can find module for a switch simple device?" do
    res = Workers.module(:irrigation_12v, "irrigation 12v power")

    assert Switch.exists?("irrigation 12v power")
    assert get_in(res, [:found?])
    assert get_in(res, [:name]) == "irrigation 12v power"
  end

  test "can find module for a reef worker?" do
    res = Workers.module(:first_mate, :reef_worker)

    assert is_map(res)
    assert res[:found?]
    assert res[:name] == :reef_worker
    assert res[:module] == Reef.FirstMate
  end

  test "can find module for a generic worker?" do
    res = Workers.module(:air, "mixtank air")

    assert is_map(res)
    assert res[:found?]
    assert res[:name] == "mixtank air"
    assert res[:module] == Reef.MixTank.Air
  end

  test "can build workers module cache from a map of workers" do
    dev_map = %{
      air: "mixtank air",
      pump: "mixtank pump",
      mixtank_temp: "mixtank heater",
      foobar: "foo bar"
    }

    res = Workers.build_module_cache(dev_map)

    assert is_map(res)

    for ident <- [:air, :pump, :mixtank_temp] do
      assert res[ident][:found?]
    end

    assert res[:air][:type] == :gen_device

    refute res[:foobar][:found?]

    refute Workers.module_cache_complete?(res)
  end

  test "can get the device module maps for all workers" do
    worker_list = Workers.all()

    assert is_list(worker_list)
    assert %{name: _, module: Reef.MixTank.Air} = hd(worker_list)
    assert length(tl(worker_list)) == 5
  end
end
