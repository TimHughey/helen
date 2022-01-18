defmodule Sally.DevAliasAidTest do
  use ExUnit.Case, async: true

  @moduletag sally: true, sally_devalias_aid: true

  setup_all do
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :devalias_just_saw]

  describe "DevAliasAid.add/1" do
    @tag device_add: [], devalias_add: []
    test "creates a new DevAlias with defaults", ctx do
      assert %{
               dev_alias: %Sally.DevAlias{pio: 0},
               device: %Sally.Device{family: "ds", mutable: false, pios: 1}
             } = ctx
    end

    @tag device_add: [], devalias_add: []
    test "does nothing when :devalias_add not present in context", ctx do
      assert %{device: %Sally.Device{}} = ctx
      refute is_map_key(ctx, :devalias)
    end

    @tag device_add: [auto: :mcp23008], devalias_add: []
    test "creates a new DevAlias to a mutable", ctx do
      assert %{
               dev_alias: %Sally.DevAlias{pio: 0},
               device: %Sally.Device{family: "i2c", mutable: true, pios: 8}
             } = ctx
    end

    @tag device_add: [auto: :mcp23008], devalias_add: [count: 4]
    test "creates multiple DevAlias", ctx do
      assert %{
               dev_alias: [%Sally.DevAlias{} | _] = dev_aliases,
               device: %Sally.Device{family: "i2c", mutable: true, pios: 8}
             } = ctx

      assert length(dev_aliases) == 4

      device_id = ctx.device.id
      Enum.all?(dev_aliases, fn dev_alias -> assert %Sally.DevAlias{device_id: ^device_id} = dev_alias end)
    end
  end

  describe "DevAliasAid.just_saw/1" do
    @tag device_add: [auto: :mcp23008], devalias_add: [count: 4]
    @tag just_saw: []
    test "invokes Sally.DevAlias.just_saw/2 for created DevAlias", ctx do
      assert %{sally_just_saw_v3: :ok, dev_alias: [%Sally.DevAlias{} | _] = dev_aliases} = ctx

      Enum.each(dev_aliases, fn %Sally.DevAlias{name: name} ->
        assert %{name: ^name} = Alfred.Name.info(name)
      end)
    end

    @tag device_add: [auto: :mcp23008], devalias_add: [count: 4]
    test "does nothing when :just_saw not present in context", ctx do
      assert %{dev_alias: [%Sally.DevAlias{} | _]} = ctx
      refute is_map_key(ctx, :sally_just_saw_v3)
    end
  end

  def devalias_add(ctx), do: Sally.DevAliasAid.add(ctx)
  def devalias_just_saw(ctx), do: Sally.DevAliasAid.just_saw(ctx)
  def device_add(ctx), do: Sally.DeviceAid.add(ctx)
  def host_add(ctx), do: Sally.HostAid.add(ctx)
  def host_setup(ctx), do: Sally.HostAid.setup(ctx)
end
