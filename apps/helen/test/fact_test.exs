defmodule FactTest do
  @moduledoc false

  use ExUnit.Case, async: true

  use HelenTestPretty

  @influx_cfg Application.compile_env!(:helen, Fact.Influx)

  @moduletag :fact

  defmacro should_be_non_empty_list(res) do
    quote bind_quoted: [res: res] do
      fail = pretty("should be non-empty list", res)
      assert is_list(res), fail
      refute [] == res
    end
  end

  defmacro should_be_non_empty_map(res) do
    quote bind_quoted: [res: res] do
      fail = pretty("should be a map", res)
      assert is_map(res), fail
      assert map_size(res) > 0, fail
    end
  end

  defmacro should_contain_key(res, what) do
    quote bind_quoted: [res: res, what: what] do
      fail = pretty("should contain #{inspect(what)}", res)

      assert Enum.find(res, false, fn
               {k, _v} -> k == what
               x -> x == what
             end),
             fail
    end
  end

  test "can get available measurements" do
    list = Fact.Influx.measurements()

    should_be_non_empty_list(list)
    should_contain_key(list, "mqtt")
  end

  test "can get known shards" do
    db = get_in(@influx_cfg, [:database])
    map = Fact.Influx.shards(db)

    should_be_non_empty_map(map)
    should_contain_key(map, :columns)
    should_contain_key(map, :name)
    should_contain_key(map, :values)

    values = map.values

    should_be_non_empty_list(values)
  end
end
