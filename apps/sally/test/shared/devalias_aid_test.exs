defmodule Sally.DevAliasAidTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag sally: true, sally_devalias_aid: true

  alias Sally.{DevAlias, DevAliasAid, Device, DeviceAid, HostAid}

  setup_all do
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :devalias_just_saw]

  describe "DevAliasAid.add/1" do
    @tag device_add: [], devalias_add: []
    test "creates a new DevAlias with defaults", ctx do
      Should.Be.Map.with_key(ctx, :dev_alias)

      device_kv = [family: "ds", mutable: false, pios: 1]
      Should.Be.Struct.with_all_key_value(ctx.device, Device, device_kv)

      devalias_kv = [pio: 0]
      Should.Be.Schema.with_all_key_value(ctx.dev_alias, DevAlias, devalias_kv)
    end

    @tag device_add: [], devalias_add: []
    test "does nothing when :devalias_add not present in context", ctx do
      Should.Be.Map.with_key(ctx, :device)
      Should.Be.Map.without_key(ctx, :devalias)
    end

    @tag device_add: [auto: :mcp23008], devalias_add: []
    test "creates a new DevAlias to a mutable", ctx do
      Should.Be.Map.with_key(ctx, :dev_alias)

      device_kv = [family: "i2c", mutable: true, pios: 8]
      Should.Be.Struct.with_all_key_value(ctx.device, Device, device_kv)

      devalias_kv = [pio: 0]
      Should.Be.Schema.with_all_key_value(ctx.dev_alias, DevAlias, devalias_kv)
    end

    @tag device_add: [auto: :mcp23008], devalias_add: [count: 4]
    test "creates multiple DevAlias", ctx do
      dev_aliases = Should.Be.Map.with_key(ctx, :dev_alias)

      Should.Be.List.with_length(dev_aliases, 4)

      want_kv = [device_id: ctx.device.id]

      for dev_alias <- dev_aliases do
        Should.Be.Schema.with_all_key_value(dev_alias, DevAlias, want_kv)
      end
    end
  end

  describe "DevAliasAid.just_saw/1" do
    @tag device_add: [auto: :mcp23008], devalias_add: [count: 4]
    @tag just_saw: []
    test "invokes Sally.just_saw/2 for created DevAlias", ctx do
      count = ctx[:devalias_add][:count] || 0
      jsr = ctx[:sally_just_saw]

      Should.Be.List.with_length(jsr, count)
    end

    @tag device_add: [auto: :mcp23008], devalias_add: [count: 4]
    test "does nothing when :just_saw not present in context", ctx do
      Should.Be.Map.with_key(ctx, :dev_alias)
      Should.Be.Map.without_key(ctx, :sally_just_saw)
    end
  end

  def devalias_add(ctx), do: DevAliasAid.add(ctx)
  def devalias_just_saw(ctx), do: DevAliasAid.just_saw(ctx)
  def device_add(ctx), do: DeviceAid.add(ctx)
  def host_add(ctx), do: HostAid.add(ctx)
  def host_setup(ctx), do: HostAid.setup(ctx)
end
