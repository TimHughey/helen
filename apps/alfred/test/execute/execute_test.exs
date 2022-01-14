defmodule Alfred.ExecuteTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_dev_alias: true, alfred_execute: true

  setup [:equipment_add, :sensor_add, :name_add, :register_add]

  describe "Alfred.Execute.execute/2" do
    @tag name_add: [type: :unk]
    test "handles unknown name", %{name: name} do
      assert %Alfred.Execute{name: ^name, rc: :not_found, detail: :none} =
               Alfred.Execute.execute([name: name, cmd: "on"], [])
    end
  end

  describe "Alfred.Test.DevAlias.execute/2" do
    @tag name_add: [type: :unk]
    test "handles unknown name", %{name: name} do
      assert %Alfred.Execute{name: ^name, rc: :not_found, detail: :none} =
               Alfred.Test.DevAlias.execute([name: name, cmd: "on"], [])
    end

    test "handles cmd equal to status" do
      names =
        Enum.map(1..3, fn _x ->
          fake_ctx = %{equipment_add: [cmd: "off"]}
          %{equipment: name} = Alfred.NamesAid.equipment_add(fake_ctx)

          name
          |> Alfred.NamesAid.binary_to_parts()
          |> Alfred.Test.DevAlias.new()
        end)

      assert :ok == Alfred.Test.DevAlias.just_saw(names)

      assert %{name: name} = List.first(names)

      assert %Alfred.Execute{detail: %{cmd: "off"}, name: ^name} =
               Alfred.Test.DevAlias.execute([name: name, cmd: "off"], [])
    end

    test "cmd different than status" do
      names =
        Enum.map(1..3, fn _x ->
          fake_ctx = %{equipment_add: [cmd: "off"]}
          %{equipment: name} = Alfred.NamesAid.equipment_add(fake_ctx)

          name
          |> Alfred.NamesAid.binary_to_parts()
          |> Alfred.Test.DevAlias.new()
        end)

      assert :ok == Alfred.Test.DevAlias.just_saw(names)

      assert %{name: name} = List.first(names)
      execute_args = [name: name, cmd: "on"]

      assert %Alfred.Execute{detail: %{cmd: "on", __execute__: %{refid: refid}}, name: ^name, rc: :pending} =
               Alfred.Test.DevAlias.execute(execute_args, [])

      assert Alfred.Broom.tracked?(refid)

      assert :ok == Alfred.Test.Command.release(refid, [])

      assert [errors: _, released: _, timeout: _, tracked: tracked] = Alfred.Broom.Metrics.counts()
      assert tracked > 0
    end
  end

  def equipment_add(ctx), do: Alfred.NamesAid.equipment_add(ctx)
  def name_add(ctx), do: Alfred.NamesAid.name_add(ctx)

  def register_add(ctx) when is_map_key(ctx, :sensor) or is_map_key(ctx, :equipment) do
    register_opts = Map.get(ctx, :register_opts, [])

    case ctx do
      %{sensor: name} -> Alfred.StatusImpl.register(name, register_opts)
      %{equipment: name} -> Alfred.StatusImpl.register(name, register_opts)
    end
    |> then(fn registered_name -> %{registered_name: registered_name} end)
  end

  def register_add(_ctx), do: :ok

  def sensor_add(ctx), do: Alfred.NamesAid.sensor_add(ctx)
end
