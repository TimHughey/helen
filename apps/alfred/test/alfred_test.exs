defmodule AlfredTest do
  use ExUnit.Case

  import Alfred.NamesAid, only: [sensor_add: 1, equipment_add: 1]

  @moduletag alfred: true, alfred_api: true

  setup [:sensor_add, :equipment_add]

  defmacrop get_name_from_ctx do
    quote do
      possible = Map.take(var!(ctx), [:sensor, :equipment, :name]) |> Map.values()
      assert [name | _] = possible

      name
    end
  end

  describe "Alfred generated Alfred.Name delegates" do
    test "name_available?/2 returns true when a name is not yet registered" do
      assert Alfred.name_available?("foobar")
    end

    @tag sensor_add: [rc: :ok, temp_f: 81.1, relhum: 65.1]
    test "name_available/2 returns false when a name is registered", ctx do
      refute get_name_from_ctx() |> Alfred.name_available?()
    end

    @tag equipment_add: []
    test "name_info/1 returns an Alfred.Name as a map", ctx do
      name = get_name_from_ctx()
      assert %{name: ^name} = Alfred.name_info(name)
    end

    test "name_missing?/1 returns true when name is not registered" do
      assert Alfred.name_missing?("foo")
    end

    @tag equipment_add: []
    test "name_missing?/2 returns true honoring [ttl_ms: 1] opts", ctx do
      name = get_name_from_ctx()

      Process.sleep(2)

      assert Alfred.name_missing?(name, ttl_ms: 1)
    end

    @tag equipment_add: []
    test "name_registered?/1 returns true when a name is registered", ctx do
      assert get_name_from_ctx() |> Alfred.name_registered?()
    end

    @tag sensor_add: [rc: :ok, temp_f: 81.1, relhum: 65.1]
    test "name_unregister/2 removes a known name", ctx do
      name = get_name_from_ctx()

      assert :ok = Alfred.name_unregister(name)
      refute Alfred.name_registered?(name)
    end
  end

  defmacro assert_good_immutable_status(status) do
    quote bind_quoted: [status: status] do
      assert %Alfred.Status{
               name: <<_name::binary>>,
               rc: :ok,
               detail: %{temp_f: _}
             } = status
    end
  end

  defmacro assert_good_mutable_status(status) do
    quote bind_quoted: [status: status] do
      assert %Alfred.Status{
               name: <<_::binary>>,
               rc: :ok,
               detail: %{cmd: <<_::binary>>}
             } = status
    end
  end

  describe "Alfred.status/2" do
    @tag sensor_add: [rc: :ok, temp_f: 81.1, relhum: 65.1]
    test "returns a well formed Alfred.Status with datapoint detail", ctx do
      name = get_name_from_ctx()
      status = Alfred.status(name, [])

      assert_good_immutable_status(status)
    end

    @tag equipment_add: []
    test "returns a well formed Alfred.Status with cmd detail", ctx do
      name = get_name_from_ctx()
      status = Alfred.status(name, [])

      assert_good_mutable_status(status)
    end

    @tag sensor_add: [rc: :ok, temp_f: 81.1, relhum: 65.1, register: false]
    test "returns an Alfred.Status with error when name unknown", ctx do
      name = get_name_from_ctx()

      assert %Alfred.Status{name: ^name, rc: :not_found} = Alfred.status(name)
    end
  end
end
