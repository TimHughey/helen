defmodule SallyStatusTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_status: true

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :command_add, :devalias_just_saw]

  describe "Sally.status(:mut_status, name, opts)" do
    test "detects unknown Alias name", _ctx do
      assert %Alfred.MutableStatus{
               name: "unknown",
               found?: false,
               cmd: "unknown",
               pending?: false,
               ttl_expired?: false
             } = Sally.status(:mut_status, "unknown", [])
    end

    @tag device_add: [auto: :pwm], devalias_add: [count: 3], devalias_just_saw: []
    test "detects ttl expired using ttl_ms opt", ctx do
      %Sally.DevAlias{name: name} = Sally.DevAliasAid.random_pick(ctx.dev_alias)

      assert %Alfred.MutableStatus{
               name: ^name,
               found?: true,
               ttl_expired?: true
             } = Sally.status(:mut_status, name, ttl_ms: 0)
    end

    @tag device_add: [auto: :pwm], devalias_add: [count: 3, ttl_ms: 50], devalias_just_saw: []
    test "detects ttl expired based on DevAlias ttl_ms", ctx do
      # allow ttl to expire
      Process.sleep(51)

      %Sally.DevAlias{name: name} = Sally.DevAliasAid.random_pick(ctx.dev_alias)

      assert %Alfred.MutableStatus{
               name: ^name,
               found?: true,
               ttl_expired?: true
             } = Sally.status(:mut_status, name, [])
    end

    @tag device_add: [auto: :pwm], devalias_add: [], devalias_just_saw: []
    @tag command_add: [cmd: "pending"]
    test "detects pending cmd", ctx do
      %Sally.DevAlias{name: name} = ctx.dev_alias
      refid = ctx.command.refid

      assert %Alfred.MutableStatus{
               name: ^name,
               cmd: "pending",
               found?: true,
               pending?: true,
               ttl_expired?: false,
               pending_refid: ^refid,
               error: :none
             } = Sally.status(:mut_status, name, [])
    end

    @tag device_add: [auto: :pwm], devalias_add: [], devalias_just_saw: []
    @tag command_add: [cmd: "unresponsive", track: true, track_timeout_ms: 0]
    test "detects unresponsive (orphaned cmd)", ctx do
      # allow track timeout to expire
      Process.sleep(100)

      %Sally.DevAlias{name: name} = ctx.dev_alias

      for _ <- 1..10, reduce: Sally.status(:mut_status, name, []) do
        %Alfred.MutableStatus{pending?: true} ->
          Process.sleep(100)
          Sally.status(:mut_status, name, [])

        %Alfred.MutableStatus{pending?: false} = acc ->
          acc
      end

      assert %Alfred.MutableStatus{
               name: ^name,
               cmd: "unknown",
               found?: true,
               pending?: false,
               ttl_expired?: false,
               error: :unresponsive
             } = Sally.status(:mut_status, name, [])
    end

    @tag device_add: [auto: :pwm], devalias_add: [], devalias_just_saw: []
    @tag command_add: [cmd: "good", ack: :immediate]
    test "detects good cmd", ctx do
      %Sally.DevAlias{name: name} = ctx.dev_alias
      cmd = ctx.command_add[:cmd]

      assert %Alfred.MutableStatus{
               name: ^name,
               cmd: ^cmd,
               found?: true,
               pending?: false,
               pending_refid: nil,
               ttl_expired?: false,
               error: :none
             } = Sally.status(:mut_status, name, [])
    end
  end
end
