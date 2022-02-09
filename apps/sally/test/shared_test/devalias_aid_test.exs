defmodule Sally.DevAliasAidTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_devalias_aid: true

  setup [:host_add, :device_add, :devalias_add]

  describe "DevAliasAid.add/1" do
    @tag device_add: [], devalias_add: []
    test "creates a new DevAlias with defaults", ctx do
      assert %{
               dev_alias: %Sally.DevAlias{pio: 0},
               device: %Sally.Device{family: "ds", mutable: false, pios: 1}
             } = ctx
    end

    @tag devalias_add: [count: 1]
    test "creates a new DevAlias with mixed opts", ctx do
      assert %{
               dev_alias: %Sally.DevAlias{pio: 0},
               device: %Sally.Device{family: "ds", mutable: false, pios: 1}
             } = ctx
    end

    @tag devalias_add: [count: 8, auto: :mcp23008]
    test "creates many DevAlias for a mcp23008 (from mixed opts)", ctx do
      assert %{
               dev_alias: [%Sally.DevAlias{}, %Sally.DevAlias{} | _] = dev_aliases,
               device: %Sally.Device{family: "i2c", mutable: true, pios: 8},
               host: %Sally.Host{authorized: true}
             } = ctx

      assert length(dev_aliases) == 8
    end

    @tag devalias_add: [auto: :mcp23008, count: 5, cmds: [history: 5, latest: :busy]]
    test "creates many DevAlias, with historical cmds and one busy", ctx do
      assert %{
               dev_alias: [%Sally.DevAlias{} = dev_alias | _] = dev_aliases,
               device: %Sally.Device{family: "i2c", mutable: true, pios: 8},
               cmd_latest: [%Sally.Command{} | _] = cmd_latest
             } = ctx

      assert Enum.all?(cmd_latest, fn execute -> match?(%{acked: false}, execute) end)

      query = Sally.DevAlias.nature_ids_query(dev_alias)
      assert ids = Sally.Repo.all(query)

      assert length(ids) == 5

      assert %Sally.DevAlias{} = Sally.DevAliasAid.find_busy(dev_aliases)
    end

    @tag devalias_add: [auto: :ds, daps: [history: 5]]
    test "creates many DevAlias, with historical datapoints", ctx do
      assert %{
               dev_alias: %Sally.DevAlias{} = dev_alias,
               device: %Sally.Device{family: "ds", mutable: false, pios: 1},
               dap_history: [%{} | _] = dap_history
             } = ctx

      assert length(dap_history) == 5

      query = Sally.DevAlias.nature_ids_query(dev_alias)
      assert ids = Sally.Repo.all(query)
      assert length(ids) == 5
    end

    @tag host_add: [], device_add: []
    test "does nothing when :devalias_add not present in context", ctx do
      assert %{device: %Sally.Device{}} = ctx
      refute is_map_key(ctx, :dev_alias)
    end

    @tag devalias_add: [auto: :pwm]
    test "creates a new DevAlias to a mutable", ctx do
      assert %{
               dev_alias: %Sally.DevAlias{pio: 0},
               device: %Sally.Device{family: "pwm", mutable: true, pios: 4}
             } = ctx
    end

    @tag devalias_add: [auto: :mcp23008, count: 4]
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
end
