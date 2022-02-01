defmodule Alfred.ExecuteTest do
  use ExUnit.Case, async: true
  use Should

  import Alfred.NamesAid, only: [equipment_add: 1, name_add: 1, sensor_add: 1]

  @moduletag alfred: true, alfred_execute: true

  setup [:equipment_add, :sensor_add, :name_add]

  defmacrop get_name_from_ctx do
    quote do
      possible = Map.take(var!(ctx), [:sensor, :equipment, :name]) |> Map.values()
      assert [name | _] = possible

      name
    end
  end

  describe "Alfred.Execute.execute/2" do
    @tag name_add: [type: :unk]
    test "handles unknown name", ctx do
      name = get_name_from_ctx()

      assert %Alfred.Execute{name: ^name, rc: :not_found, detail: :none} =
               Alfred.Execute.execute([name: name, cmd: "on"], [])
    end
  end

  describe "Alfred.Test.DevAlias.execute/2" do
    @tag name_add: [type: :unk]
    test "handles unknown name", ctx do
      name = get_name_from_ctx()

      assert %Alfred.Execute{name: ^name, rc: :not_found, detail: :none} =
               Alfred.Test.DevAlias.execute([name: name, cmd: "on"], [])
    end

    @tag equipment_add: [cmd: "off"]
    test "handles cmd equal to status", ctx do
      name = get_name_from_ctx()

      assert %Alfred.Execute{rc: :ok, detail: %{cmd: "off"}, name: ^name} =
               Alfred.Test.DevAlias.execute([name: name, cmd: "off"], [])
    end

    @tag equipment_add: [cmd: "off"]
    test "cmd different than status", ctx do
      name = get_name_from_ctx()
      execute_args = [name: name, cmd: "on"]

      assert %Alfred.Execute{detail: %{cmd: "on", __execute__: %{refid: refid}}, name: ^name, rc: :busy} =
               Alfred.Test.DevAlias.execute(execute_args, [])

      assert Alfred.Track.tracked?(refid)

      assert :ok == Alfred.Test.Command.release(refid, [])

      assert [errors: _, released: _, timeout: _, tracked: tracked] = Alfred.Track.Metrics.counts()
      assert tracked > 0
    end
  end
end
