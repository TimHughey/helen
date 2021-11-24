defmodule Sally.HostAidTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag sally: true, sally_host_aid: true

  alias Sally.{Host, HostAid}

  setup [:host_add, :host_setup]

  describe "HostAid.add/1" do
    @tag host_add: []
    test "inserts a new Host with defaults", ctx do
      Should.Be.Map.with_key(ctx, :host)
      Should.Be.Struct.named(ctx.host, Host)
    end

    test "does nothing when :host_add not present in context", ctx do
      Should.Be.Map.without_key(ctx, :host)
    end
  end

  describe "HostAid.setup/1" do
    @tag host_add: []
    @tag host_setup: []
    test "setups a host", ctx do
      Should.Be.Map.with_key(ctx, :host)
      Should.Be.Struct.with_all_key_value(ctx.host, Host, authorized: true)
    end

    @tag host_add: []
    test "does nothing when :host_setup not present in context", ctx do
      Should.Be.Map.with_key(ctx, :host)
      Should.Be.Struct.with_all_key_value(ctx.host, Host, authorized: false)
    end
  end

  def host_add(ctx), do: HostAid.add(ctx)
  def host_setup(ctx), do: HostAid.setup(ctx)
end
