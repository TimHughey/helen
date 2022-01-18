defmodule Alfred.NameTest do
  use ExUnit.Case, async: true
  use Should

  import Alfred.NamesAid, only: [equipment_add: 1]

  @moduletag alfred: true, alfred_name: true

  setup [:equipment_add]

  defmacro assert_registered_name(ctx, :ok) do
    quote bind_quoted: [ctx: ctx] do
      assert %{registered_name: %{name: <<_::binary>> = name, rc: :ok}} = ctx
      assert Alfred.name_registered?(name)

      name
    end
  end

  # defmacro assert_registered_name(ctx, :ok) do
  #   quote bind_quoted: [ctx: ctx] do
  #     assert %{registered_name: %{name: <<_::binary>> = name, pid: :ok}} = ctx
  #     refute Alfred.Name.missing?(name)
  #
  #     name
  #   end
  # end

  describe "Alfred.Name.callback/2" do
    test "handles an unregistered name" do
      assert {:not_found, "foo"} = Alfred.Name.callback("foo", :status)
    end

    @tag equipment_add: []
    test "handles a registered name", ctx do
      name = assert_registered_name(ctx, :ok)

      assert {Alfred.Test.DevAlias, 2} = Alfred.Name.callback(name, :status)
      assert {Alfred.Test.DevAlias, 2} = Alfred.Name.callback(name, :execute)
    end
  end

  describe "Alfred.Name.info/1" do
    test "handles unregistered name" do
      assert {:not_found, "foo"} = Alfred.Name.info("foo")
    end

    @tag equipment_add: []
    test "returns info for a registered name", ctx do
      name = assert_registered_name(ctx, :ok)

      assert %{
               name: ^name,
               callbacks: %{
                 execute: {Alfred.Test.DevAlias, 2},
                 status: {Alfred.Test.DevAlias, 2}
               },
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
      name = assert_registered_name(ctx, :ok)

      refute Alfred.Name.missing?(name, [])
      refute Alfred.Name.missing?(ctx.registered_name.dev_alias, [])
    end

    @tag equipment_add: []
    test "honors opts ttl_ms", ctx do
      name = assert_registered_name(ctx, :ok)

      assert Alfred.Name.missing?(name, ttl_ms: 0)
    end

    @tag equipment_add: [ttl_ms: 25, register: [ttl_ms: 100]]
    test "honors registered ttl_ms", ctx do
      name = assert_registered_name(ctx, :ok)

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
      assert_registered_name(ctx, :ok)
    end

    @tag equipment_add: []
    test "handles previously registered name", ctx do
      name = assert_registered_name(ctx, :ok)

      assert :ok = Alfred.Name.register(name, [])
    end
  end

  describe "Alfred.Name.seen_at/1" do
    test "handles an unregistered name" do
      assert {:not_found, "foo"} = Alfred.Name.seen_at("foo")
    end

    @tag equipment_add: []
    test "handles a registered name", ctx do
      name = assert_registered_name(ctx, :ok)

      assert %DateTime{} = Alfred.Name.seen_at(name)
      assert %DateTime{} = Alfred.Name.seen_at(ctx.registered_name.dev_alias)
    end
  end

  describe "Alfred.Name.unregister/1" do
    test "handles unregistered name" do
      assert :ok = Alfred.Name.unregister("foo")
    end

    @tag equipment_add: []
    test "handles a registered name", ctx do
      name = assert_registered_name(ctx, :ok)

      assert :ok = Alfred.Name.unregister(name)
      refute Alfred.name_registered?(name)

      # NOTE: must do this reduction due to Registry delayed registration release
      Enum.reduce(1..10, :check, fn
        _, :check ->
          if Registry.lookup(Alfred.Name.Registry, name) == [] do
            :unregistered
          else
            Process.sleep(1)
            :check
          end

        _, :unregistered = acc ->
          acc
      end)

      assert [] = Registry.lookup(Alfred.Name.Registry, name)
    end
  end
end
