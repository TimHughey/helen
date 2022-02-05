defmodule Alfred.NameTest do
  use ExUnit.Case, async: true
  use Alfred.TestAid

  @moduletag alfred: true, alfred_name: true

  setup [:equipment_add]

  defmacro assert_registered_name do
    quote do
      ctx = var!(ctx)

      assert %{dev_alias: %Alfred.DevAlias{name: name, register: pid} = dev_alias} = ctx
      assert is_pid(pid) and Process.alive?(pid)
      assert Alfred.name_registered?(name)

      name
    end
  end

  describe "Alfred.Name.info/1" do
    test "handles unregistered name" do
      assert {:not_found, "foo"} = Alfred.Name.info("foo")
    end

    @tag equipment_add: []
    test "returns info for a registered name", ctx do
      name = assert_registered_name()

      assert %{
               name: ^name,
               callbacks: %{
                 execute_cmd: {Alfred.DevAlias, 2},
                 status_lookup: {Alfred.DevAlias, 2}
               },
               module: Alfred.DevAlias,
               nature: :cmds,
               seen_at: %DateTime{},
               ttl_ms: 5_000
             } = Alfred.Name.info(name)
    end
  end

  describe "Alfred.Name.missing?/2" do
    test "handles an unregistered name" do
      assert Alfred.Name.missing?("foo", [])
    end

    @tag equipment_add: []
    test "handles a registered name", ctx do
      name = assert_registered_name()

      refute Alfred.Name.missing?(name, [])
      refute Alfred.Name.missing?(ctx.dev_alias, [])
    end

    @tag equipment_add: []
    test "honors opts ttl_ms", ctx do
      name = assert_registered_name()

      assert Alfred.Name.missing?(name, ttl_ms: 0)
    end

    @tag equipment_add: [ttl_ms: 25, register: [ttl_ms: 100]]
    test "honors registered ttl_ms", ctx do
      name = assert_registered_name()

      # NOTE: confirm the correct ttl_ms opt made it to Alfred.Name.register/2
      assert %{ttl_ms: 100} = Alfred.name_info(name)

      refute Alfred.Name.missing?(name, []), "ttl should not be expired (not missing)"

      Process.sleep(101)

      assert Alfred.Name.missing?(name, []), "ttl should be expired (missing)"
    end
  end

  describe "Alfred.Name.register/2" do
    @tag equipment_add: []
    test "handles unregistered name", ctx do
      assert_registered_name()
    end

    @tag equipment_add: []
    test "handles previously registered name", ctx do
      _name = assert_registered_name()

      previously_registered = Alfred.DevAlias.register(ctx.dev_alias, [])
      assert previously_registered == ctx.dev_alias
    end
  end

  describe "Alfred.Name.all_registered/0" do
    @tag equipment_add: []
    test "handles previously registered name", ctx do
      name = assert_registered_name()

      all = Alfred.name_all_registered()

      assert Enum.any?(all, &match?(^name, &1))
    end
  end

  describe "Alfred.Name.seen_at/1" do
    test "handles an unregistered name" do
      assert {:not_found, "foo"} = Alfred.Name.seen_at("foo")
    end

    @tag equipment_add: []
    test "handles a registered name", ctx do
      name = assert_registered_name()

      assert %DateTime{} = Alfred.Name.seen_at(name)
      assert %DateTime{} = Alfred.Name.seen_at(ctx.dev_alias)
    end
  end

  describe "Alfred.Name.unregister/1" do
    test "handles unregistered name" do
      assert :ok = Alfred.Name.unregister("foo")
    end

    @tag equipment_add: []
    test "handles a registered name", ctx do
      name = assert_registered_name()

      assert :ok = Alfred.DevAlias.unregister(%{name: name})
      refute Alfred.name_registered?(name)

      # NOTE: must do this reduction due to Registry delayed registration release
      Enum.reduce_while(1..10, nil, fn
        _, _ ->
          if Registry.lookup(Alfred.Name.Registry, name) == [] do
            {:halt, :unregistered}
          else
            Process.sleep(1)
            {:cont, nil}
          end
      end)

      assert [] = Registry.lookup(Alfred.Name.Registry, name)
    end
  end
end
