defmodule Sally.HostAidTest do
  use ExUnit.Case, async: true

  @moduletag sally: true, sally_host_aid: true

  setup [:host_add, :host_setup]

  describe "HostAid.add/1" do
    @tag host_add: []
    test "inserts a new Host with defaults", ctx do
      assert %{host: %Sally.Host{}} = ctx
    end

    test "does nothing when :host_add not present in context", ctx do
      refute is_map_key(ctx, :host)
    end
  end

  describe "HostAid.setup/1" do
    @tag host_add: []
    @tag host_setup: []
    test "setups a host", ctx do
      assert %{host: %Sally.Host{authorized: true}} = ctx
    end

    @tag host_add: []
    test "does nothing when :host_setup not present in context", ctx do
      assert %{host: %Sally.Host{authorized: false}} = ctx
    end
  end

  def host_add(ctx), do: Sally.HostAid.add(ctx)
  def host_setup(ctx), do: Sally.HostAid.setup(ctx)
end
