defmodule Alfred.StatusTest do
  use ExUnit.Case, async: true
  use Alfred.TestAid

  @moduletag alfred: true, alfred_status: true

  setup [:equipment_add, :sensor_add, :sensors_add, :name_add]

  describe "Alfred.Status.status/2" do
    @tag name_add: [type: :unk]
    test "handles unknown name", %{name: name} do
      assert %Alfred.Status{name: ^name, detail: :none, rc: :not_found} = Alfred.status(name, [])
    end
  end

  describe "Alfred.Status.of_name/2" do
    @tag name_add: [type: :unk]
    test "handles unknown name", %{name: name} do
      assert %Alfred.Status{name: ^name, detail: :none, rc: :not_found} = Alfred.status(name, [])
    end

    @tag sensor_add: [temp_f: 78.0]
    test "handles well-formed sensor", %{sensor: name} do
      assert %Alfred.Status{name: ^name, detail: %{temp_f: _}, rc: :ok} = Alfred.status(name, [])
    end

    @tag equipment_add: [cmd: "on"]
    test "handles well-formed equipment", %{equipment: name} do
      assert %Alfred.Status{name: ^name, detail: %{cmd: "on"}, rc: :ok} = Alfred.status(name, [])
    end

    @tag equipment_add: [cmd: "on", busy: true]
    test "handles equipment busy", %{equipment: name} do
      assert %Alfred.Status{name: ^name, detail: %{cmd: "on"}, rc: :busy} = Alfred.status(name, [])
    end

    @tag equipment_add: [cmd: "on", timeout: true]
    test "handles equipment timeout", %{equipment: name} do
      status = Alfred.status(name, [])

      assert %Alfred.Status{name: ^name, detail: %{cmd: "on"}, rc: rc} = status
      assert {:timeout, ms} = rc
      assert ms > 10
    end

    @tag equipment_add: [cmd: "on", expired_ms: 15_000]
    test "handles expired equipment", %{equipment: name} do
      assert %Alfred.Status{name: ^name, detail: :none, rc: rc} = Alfred.status(name, [])

      assert {:ttl_expired, expired_ms} = rc
      assert_in_delta(15_000, expired_ms, 150)
    end
  end

  describe "Alfred.status/2" do
    @tag sensors_add: []
    test "invokes correct callback module", ctx do
      assert %{sensors: sensors} = ctx

      name = Enum.random(sensors)

      assert %Alfred.Status{name: ^name, detail: %{temp_f: temp_f}} = Alfred.status(name)
      assert_in_delta(temp_f, 11.0, 10.0)
    end
  end
end
