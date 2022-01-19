defmodule Sally.DispatchAidTest do
  use ExUnit.Case, async: true

  @moduletag sally: true, sally_dispatch_aid: true

  setup [:host_add, :host_setup, :device_add, :devalias_add, :devalias_just_saw, :dispatch_add]

  describe "Sally.DispatchAid.add/1" do
    @tag host_add: [], dispatch_add: [callback: :none, subsystem: "host", category: "startup"]
    test "creates a host startup Dispatch for a known host", ctx do
      category = ctx.dispatch_add[:category]
      assert %Sally.Dispatch{valid?: true, category: ^category} = ctx.dispatch
    end

    @tag dispatch_add: [callback: :none, subsystem: "host", category: "boot"]
    test "creates a host boot Dispatch for a unique host", ctx do
      category = ctx.dispatch_add[:category]
      assert %Sally.Dispatch{valid?: true, category: ^category} = ctx.dispatch
    end
  end

  def dispatch_add(ctx), do: Sally.DispatchAid.add(ctx)
  def devalias_add(ctx), do: Sally.DevAliasAid.add(ctx)
  def devalias_just_saw(ctx), do: Sally.DevAliasAid.just_saw(ctx)
  def device_add(ctx), do: Sally.DeviceAid.add(ctx)
  def host_add(ctx), do: Sally.HostAid.add(ctx)
  def host_setup(ctx), do: Sally.HostAid.setup(ctx)
end
