defmodule HelenWorkersModCacheTest do
  @moduledoc false

  use Timex
  use ExUnit.Case

  alias Helen.Workers.ModCache

  test "can find module for a pwm simple device?" do
    res = ModCache.module(:front_leds, "front leds evergreen")

    assert PulseWidth.exists?("front leds evergreen")
    assert get_in(res, [:found?])
    assert get_in(res, [:name]) == "front leds evergreen"
  end

  test "can find module for a switch simple device?" do
    res = ModCache.module(:irrigation_12v, "irrigation 12v power")

    assert Switch.exists?("irrigation 12v power")
    assert get_in(res, [:found?])
    assert get_in(res, [:name]) == "irrigation 12v power"
  end

  test "can find module for a reef worker?" do
    res = ModCache.module(:first_mate, :reef_worker)

    assert is_map(res)
    assert res[:found?]
    assert res[:name] == :reef_worker
    assert res[:module] == Reef.FirstMate
  end

  test "can find module for a generic worker?" do
    res = ModCache.module(:air, "mixtank air")

    assert is_map(res)
    assert res[:found?]
    assert res[:name] == "mixtank air"
    assert res[:module] == Reef.MixTank.Air
  end

  test "can get the device module maps for all workers" do
    worker_list = ModCache.all()

    assert is_list(worker_list)
    assert %{name: _, module: Reef.MixTank.Air} = hd(worker_list)
    assert length(tl(worker_list)) == 5
  end
end
