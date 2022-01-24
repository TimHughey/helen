defmodule Sally.DispatchAidTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_dispatch_aid: true

  setup [:dispatch_add]

  describe "Sally.DispatchAid.add/1" do
    @tag dispatch_add: [subsystem: "host", category: "startup", host: []]
    test "creates a host startup Dispatch for an existing host", ctx do
      category = ctx.dispatch_add[:category]

      assert %{dispatch: %Sally.Dispatch{} = dispatch} = ctx
      assert %{category: ^category, payload: <<136, _::binary>>} = dispatch
    end

    @tag dispatch_add: [subsystem: "host", category: "boot", host: [:ident_only]]
    test "creates a host boot Dispatch for a unique host", ctx do
      category = ctx.dispatch_add[:category]

      assert %{dispatch: %Sally.Dispatch{} = dispatch} = ctx
      assert %{category: ^category, payload: <<133, _::binary>>} = dispatch
    end

    @tag dev_alias_opts: [auto: :pwm, cmds: [history: 1, latest: :pending]]
    @tag dispatch_add: [subsystem: "mut", category: "cmdack"]
    test "creates a mutable cmdack Dispatch", ctx do
      category = ctx.dispatch_add[:category]

      assert %{dispatch: %Sally.Dispatch{} = dispatch} = ctx
      assert %{category: ^category, payload: <<130, _::binary>>} = dispatch
    end

    @tag dev_alias_opts: [auto: :pwm, cmds: [history: 1]]
    @tag dispatch_add: [subsystem: "mut", category: "status"]
    test "creates a mutable status Dispatch", ctx do
      category = ctx.dispatch_add[:category]

      assert %{dispatch: %Sally.Dispatch{} = dispatch} = ctx
      assert %{category: ^category, payload: <<131, _::binary>>} = dispatch
    end

    @tag dev_alias_opts: [auto: :ds, daps: [history: 5]]
    @tag dispatch_add: [subsystem: "immut", category: "celsius"]
    test "creates an immmutable status Dispatch (celsius)", ctx do
      category = ctx.dispatch_add[:category]

      assert %{dispatch: %Sally.Dispatch{} = dispatch} = ctx
      assert %{category: ^category, payload: <<133, _::binary>>} = dispatch
    end
  end

  describe "Sally.DispatchAid.make_filter/1 creates the correct filter for" do
    @tag dispatch_add: [subsystem: "host", category: "startup", host: []]
    test "a host startup message", ctx do
      assert %{dispatch: %Sally.Dispatch{} = dispatch} = ctx

      assert [_ | _] = Sally.DispatchAid.make_filter(dispatch)
    end

    @tag dev_alias_opts: [:prereqs, auto: :pwm, cmds: [history: 1, latest: :pending]]
    @tag dispatch_add: [subsystem: "mut", category: "cmdack"]
    test "a mutable cmdack message", ctx do
      assert %{dispatch: %Sally.Dispatch{} = dispatch} = ctx

      assert [_ | _] = Sally.DispatchAid.make_filter(dispatch)
    end
  end
end
