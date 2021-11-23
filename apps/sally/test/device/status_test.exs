defmodule SallyStatusTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag sally: true, sally_status: true

  alias Alfred.MutableStatus
  alias Sally.{DevAlias, DevAliasAid}

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :command_add, :devalias_just_saw]

  describe "Sally.status(:mutable, name, opts)" do
    test "detects unknown Alias name", _ctx do
      want_kv = [name: "unknown", found?: false, cmd: "unknown", pending?: false, ttl_expired?: false]

      Sally.status(:mutable, "unknown", [])
      |> Should.Be.Struct.with_all_key_value(MutableStatus, want_kv)
    end

    @tag device_add: [auto: :pwm], devalias_add: [count: 3], devalias_just_saw: []
    test "detects ttl expired using ttl_ms opt", ctx do
      %DevAlias{name: name} = DevAliasAid.random_pick(ctx.dev_alias)
      want_kv = [name: name, found?: true, ttl_expired?: true]

      Sally.status(:mutable, name, ttl_ms: 0)
      |> Should.Be.Struct.with_all_key_value(MutableStatus, want_kv)
    end

    @tag device_add: [auto: :pwm], devalias_add: [count: 3, ttl_ms: 50], devalias_just_saw: []
    test "detects ttl expired based on DevAlias ttl_ms", ctx do
      # allow ttl to expire
      Process.sleep(51)

      %DevAlias{name: name} = DevAliasAid.random_pick(ctx.dev_alias)
      want_kv = [name: name, found?: true, ttl_expired?: true]

      Sally.status(:mutable, name, [])
      |> Should.Be.Struct.with_all_key_value(MutableStatus, want_kv)
    end

    @tag device_add: [auto: :pwm], devalias_add: [], devalias_just_saw: []
    @tag command_add: [cmd: "pending"]
    test "detects pending cmd", ctx do
      %DevAlias{name: name} = ctx.dev_alias

      want_kv = [
        name: name,
        cmd: "pending",
        ttl_expired?: false,
        found?: true,
        pending?: true,
        pending_refid: ctx.command.refid,
        error: :none
      ]

      Sally.status(:mutable, name, [])
      |> Should.Be.Struct.with_all_key_value(MutableStatus, want_kv)
    end

    @tag device_add: [auto: :pwm], devalias_add: [], devalias_just_saw: []
    @tag command_add: [cmd: "unresponsive", track: true, track_timeout_ms: 0]
    test "detects unresponsive (orphaned cmd)", ctx do
      # allow track timeout to expire
      Process.sleep(100)

      %DevAlias{name: name} = ctx.dev_alias

      for _ <- 1..10, reduce: Sally.status(:mutable, name, []) do
        %MutableStatus{pending?: true} ->
          Process.sleep(100)
          Sally.status(:mutable, name, [])

        %MutableStatus{pending?: false} = acc ->
          acc
      end

      want_kv = [
        name: name,
        cmd: "unknown",
        ttl_expired?: false,
        found?: true,
        pending?: false,
        error: :unresponsive
      ]

      Sally.status(:mutable, name, [])
      |> Should.Be.Struct.with_all_key_value(MutableStatus, want_kv)
    end

    @tag device_add: [auto: :pwm], devalias_add: [], devalias_just_saw: []
    @tag command_add: [cmd: "good", ack: :immediate]
    test "detects good cmd", ctx do
      %DevAlias{name: name} = ctx.dev_alias

      want_kv = [
        name: name,
        cmd: ctx.command_add[:cmd],
        ttl_expired?: false,
        found?: true,
        pending?: false,
        pending_refid: nil,
        error: :none
      ]

      Sally.status(:mutable, name, [])
      |> Should.Be.Struct.with_all_key_value(MutableStatus, want_kv)
    end
  end

  def command_add(ctx), do: Sally.CommandAid.add(ctx)
  def devalias_add(ctx), do: Sally.DevAliasAid.add(ctx)
  def devalias_just_saw(ctx), do: Sally.DevAliasAid.just_saw(ctx)
  def device_add(ctx), do: Sally.DeviceAid.add(ctx)
  def dispatch_add(ctx), do: Sally.DispatchAid.add(ctx)
  def host_add(ctx), do: Sally.HostAid.add(ctx)
  def host_setup(ctx), do: Sally.HostAid.setup(ctx)
end
