defmodule AlfredSimTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_sim: true

  describe "AlfredSim.parse_names/1" do
    setup [:setup_parse_name]

    @tag name: "imm sensor1 ok tempf_82.1"
    test "returns parts map with single data point", %{name_parts: np} do
      should_be_map_with_keys(np, [:data, :rc, :type])
      should_be_equal(np, %{data: "tempf_82.1", rc: "ok", type: "imm"})
    end

    @tag name: "imm sensor1 ok tempf_82.1 relhum_65"
    test "returns parts map with two data points", %{name_parts: np} do
      should_be_map_with_keys(np, [:data, :rc, :type])
      should_be_equal(np, %{data: "tempf_82.1 relhum_65", rc: "ok", type: "imm"})
    end

    @tag name: "mut power1 expired_10000 cmd_on"
    test "returns parts map with expired rc", %{name_parts: np} do
      should_be_map_with_keys(np, [:data, :rc, :type])
      should_be_equal(np, %{data: "cmd_on", rc: "expired_10000", type: "mut"})
    end
  end

  defp setup_parse_name(%{name: name} = ctx) do
    parts = AlfredSim.parse_name(name)

    Map.put(ctx, :name_parts, parts)
  end

  defp setup_parse_name(ctx), do: ctx
end
