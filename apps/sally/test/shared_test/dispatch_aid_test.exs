defmodule Sally.DispatchAidTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag sally: true, sally_dispatch_aid: true

  alias Sally.Dispatch
  # alias Sally.{DispatchAid, DevAlias, DevAliasAid, Device, DeviceAid, HostAid}

  setup_all do
    # {:ok, %{host_add: [], host_setup: []}}
    {:ok, %{}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :devalias_just_saw, :dispatch_add]

  describe "Sally.DispatchAid.add/1" do
    @tag host_add: [], dispatch_add: [subsystem: "host", category: "startup"]
    test "creates a host startup Dispatch for a known host", ctx do
      want_kv = [valid?: true, category: ctx.dispatch_add[:category]]

      Should.Be.Struct.with_all_key_value(ctx.dispatch, Dispatch, want_kv)
    end

    @tag dispatch_add: [subsystem: "host", category: "boot"]
    test "creates a host boot Dispatch for a unique host", ctx do
      want_kv = [valid?: true, category: ctx.dispatch_add[:category]]

      Should.Be.Struct.with_all_key_value(ctx.dispatch, Dispatch, want_kv)
    end
  end

  def dispatch_add(ctx), do: Sally.DispatchAid.add(ctx)
  def devalias_add(ctx), do: Sally.DevAliasAid.add(ctx)
  def devalias_just_saw(ctx), do: Sally.DevAliasAid.just_saw(ctx)
  def device_add(ctx), do: Sally.DeviceAid.add(ctx)
  def host_add(ctx), do: Sally.HostAid.add(ctx)
  def host_setup(ctx), do: Sally.HostAid.setup(ctx)
end
