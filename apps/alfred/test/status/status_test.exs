defmodule Alfred.StatusTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_status: true

  setup [:equipment_add, :sensor_add, :name_add, :register_add]

  describe "Alfred.Status.status/2" do
    @tag name_add: [type: :unk]
    test "handles unknown name", %{name: name} do
      assert %Alfred.Status{name: ^name, detail: :none, rc: :not_found} = Alfred.Status.status(name, [])
    end
  end

  describe "Alfred.Status.of_name/2" do
    @tag name_add: [type: :unk]
    test "handles unknown name", %{name: name} do
      assert %Alfred.Status{name: ^name, detail: :none, rc: :not_found} = Alfred.StatusImpl.status(name, [])
    end

    @tag sensor_add: [temp_f: 78.0]
    test "handles well-formed sensor", %{sensor: name} do
      assert %Alfred.Status{name: ^name, detail: %{temp_f: _}, rc: :ok} = Alfred.StatusImpl.status(name, [])
    end

    @tag equipment_add: [cmd: "on"]
    test "handles well-formed equipment", %{equipment: name} do
      assert %Alfred.Status{name: ^name, detail: %{cmd: "on"}, rc: :ok} = Alfred.StatusImpl.status(name, [])
    end

    @tag equipment_add: [cmd: "on", pending: true]
    test "handles pending equipment", %{equipment: name} do
      assert %Alfred.Status{name: ^name, detail: %{cmd: "on"}, rc: :pending} =
               Alfred.StatusImpl.status(name, [])
    end

    @tag equipment_add: [cmd: "on", orphaned: true]
    test "handles orphaned equipment", %{equipment: name} do
      assert %Alfred.Status{name: ^name, detail: %{cmd: "on"}, rc: :orphan} =
               Alfred.StatusImpl.status(name, [])
    end

    @tag equipment_add: [cmd: "on", expired_ms: 15_000]
    test "handles expired equipment", %{equipment: name} do
      assert %Alfred.Status{name: ^name, detail: :none, rc: {:ttl_expired, expired_ms}} =
               Alfred.StatusImpl.status(name, [])

      assert_in_delta(15_000, expired_ms, 150)
    end
  end

  describe "Alfred.status_v3/2" do
    test "invokes correct callback module" do
      names =
        Enum.map(1..3, fn _x ->
          fake_ctx = %{sensor_add: [temp_f: 71.2]}
          %{sensor: name} = Alfred.NamesAid.sensor_add(fake_ctx)

          name
          |> Alfred.NamesAid.binary_to_parts()
          |> Alfred.Test.DevAlias.new()
        end)

      assert :ok = Alfred.Test.DevAlias.just_saw(names)

      assert %{name: name} = List.first(names)

      assert %Alfred.Status{name: ^name, detail: %{temp_f: _}} = Alfred.status_v3(name)
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
