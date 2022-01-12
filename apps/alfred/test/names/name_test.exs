defmodule Alfred.NameTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_name: true

  setup_all do
    {:ok, %{equipment_add: []}}
  end

  setup [:opts_add, :equipment_add, :register_add]

  defmacro assert_registered_name(ctx, :ok_pid) do
    quote bind_quoted: [ctx: ctx] do
      assert %{registered_name: %{name: <<_::binary>> = name, pid: {:ok, pid}}} = ctx
      assert Process.alive?(pid)

      name
    end
  end

  defmacro assert_registered_name(ctx, :ok) do
    quote bind_quoted: [ctx: ctx] do
      assert %{registered_name: %{name: <<_::binary>> = name, pid: :ok}} = ctx
      refute Alfred.Name.missing?(name)

      name
    end
  end

  describe "Alfred.Name.register/2" do
    @tag register_add: []
    test "handles unregistered name", ctx do
      assert_registered_name(ctx, :ok_pid)
    end

    @tag register_add: []
    test "handles previously registered name", ctx do
      name = assert_registered_name(ctx, :ok_pid)

      assert :ok = Alfred.Name.register(name, [])
    end
  end

  describe "Alfred.Name.seen_at/1" do
    test "handles an unregistered name" do
      assert {:not_found, "foo"} = Alfred.Name.seen_at("foo")
    end

    @tag register_add: []
    test "handles a registered name", ctx do
      name = assert_registered_name(ctx, :ok_pid)

      assert %DateTime{} = Alfred.Name.seen_at(name)
    end
  end

  describe "Alfred.Name.missing?/2" do
    test "handles an unregistered name" do
      assert Alfred.Name.missing?("foo", [])
    end

    @tag register_add: []
    test "handles a registered name", ctx do
      name = assert_registered_name(ctx, :ok_pid)

      refute Alfred.Name.missing?(name, [])
    end

    @tag register_add: []
    test "honors opts ttl_ms", ctx do
      name = assert_registered_name(ctx, :ok_pid)

      assert Alfred.Name.missing?(name, ttl_ms: 0)
    end

    @tag register_add: [ttl_ms: 1]
    test "honors registered ttl_ms", ctx do
      name = assert_registered_name(ctx, :ok_pid)

      refute Alfred.Name.missing?(name, [])

      Process.sleep(2)

      assert Alfred.Name.missing?(name, [])
    end
  end

  describe "Alfred.Name.unregister/1" do
    test "handles unregistered name" do
      assert :ok = Alfred.Name.unregister("foo")
    end

    @tag register_add: []
    test "handles a registered name", ctx do
      name = assert_registered_name(ctx, :ok_pid)

      %{registered_name: %{pid: {:ok, pid}}} = ctx

      assert :ok = Alfred.Name.unregister(name)
      refute Process.alive?(pid)

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

  describe "Alfred.Name.info/1" do
    test "handles unregistered name" do
      assert {:not_found, "foo"} = Alfred.Name.info("foo")
    end

    @tag register_add: []
    test "returns info for a registered name", ctx do
      name = assert_registered_name(ctx, :ok_pid)

      assert %{
               name: ^name,
               callbacks: %{
                 execute: {Alfred.Name, :callback_default},
                 status: {Alfred.Name, :callback_default}
               },
               seen_at: %DateTime{},
               ttl_ms: 30_000
             } = Alfred.Name.info(name)
    end
  end

  describe "Alfred.Names misc" do
    @tag equipment_add: []
    test "can get all registered names", %{equipment: name} do
      {:ok, pid} = Alfred.Name.register(name, callback: fn _ -> :callback end)
      assert Process.alive?(pid)

      assert [<<_::binary>> | _] = Alfred.Names.registered()
    end
  end

  def opts_add(ctx) do
    opts_default = [callback: fn _what, _opts -> self() end]

    case ctx do
      %{opts_add: opts} -> %{opts: Keyword.merge(opts_default, opts)}
      _ -> %{opts: opts_default}
    end
  end

  def equipment_add(ctx), do: Alfred.NamesAid.equipment_add(ctx)

  def register_add(%{register_add: opts, equipment: name}) do
    %{registered_name: %{name: name, pid: Alfred.Name.register(name, opts)}}
  end

  def register_add(_ctx), do: :ok
end
