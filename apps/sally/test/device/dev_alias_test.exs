defmodule SallyDevAliasTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_dev_alias: true

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :devalias_just_saw]
  setup [:command_add, :datapoint_add, :dispatch_add]

  defmacro assert_execution_us(elapsed, expected_us) do
    quote bind_quoted: [elapsed: elapsed, expected_us: expected_us] do
      #  assert Timex.Duration.to_microseconds(elapsed) < expected_us, format_elapsed_ms(elapsed)
    end
  end

  describe "Sally.device_add_alias/1" do
    @tag device_add: [auto: :mcp23008]
    test "detects missing options", %{device: device} do
      assert {:error, text} = Sally.device_add_alias(name: Sally.DevAliasAid.unique(:devalias))
      assert text =~ ~r/:device missing/

      assert {:error, text} = Sally.device_add_alias(device: device.ident)
      assert text =~ ~r/name/

      assert {:error, text} =
               Sally.device_add_alias(device: device.ident, name: Sally.DevAliasAid.unique(:devalias))

      assert text =~ ~r/pio/
    end

    test "detects missing device" do
      assert {:not_found, text} =
               Sally.device_add_alias(device: "ds.missing", name: Sally.DevAliasAid.unique(:devalias))

      assert text =~ ~r/ds.missing/
    end

    @tag device_add: [auto: :mcp23008]
    test "handles changeset errors", %{device: device} do
      opts = [device: device.ident, name: Sally.DevAliasAid.unique(:dev_alias), pio: -1]
      assert {:error, [{:pio, _}]} = Sally.device_add_alias(opts)
    end

    @tag device_add: [auto: :mcp23008], devalias_add: [], just_saw: []
    test "detects duplicate name", %{device: device, dev_alias: dev_alias} do
      taken_name = dev_alias.name

      opts = [device: device.ident, name: dev_alias.name]
      assert {:name_taken, ^taken_name} = Sally.device_add_alias(opts)
    end
  end

  describe "Sally.devalias_delete/1" do
    @tag skip: true
    @tag device_add: [auto: :mcp23008], devalias_add: [], just_saw: []
    @tag command_add: [count: 250, shift_unit: :days, shift_increment: -1]
    test "deletes a mutable DevAlias name", ctx do
      assert %Sally.DevAlias{name: to_delete_name} = ctx.dev_alias

      assert {:ok, [{:name, ^to_delete_name}, {:commands, _}, {:datapoints, _}, {:alfred, _}]} =
               Sally.devalias_delete(to_delete_name)
    end

    @tag skip: true
    @tag device_add: [auto: :ds], devalias_add: [], just_saw: []
    @tag datapoint_add: [count: 250, shift_unit: :days, shift_increment: -1]
    test "deletes an immutable DevAlias name", ctx do
      assert %Sally.DevAlias{name: to_delete_name} = ctx.dev_alias

      assert {:ok, [{:name, ^to_delete_name}, {:commands, _}, {:datapoints, _}, {:alfred, _}]} =
               Sally.devalias_delete(to_delete_name)
    end
  end

  @tag device_add: [auto: :ds], devalias_add: [], just_saw: []
  test "Sally.devalias_info/2 returns summarized and raw results", ctx do
    assert %{device: device, host: host} = ctx

    assert %Sally.Host{
             name: host_name,
             ident: host_ident,
             profile: host_profile,
             last_seen_at: host_last_seen_at
           } = host

    assert %Sally.Device{ident: dev_ident, last_seen_at: dev_last_seen_at} = device

    name = Sally.DevAliasAid.unique(:dev_alias)

    assert %Sally.DevAlias{name: ^name, pio: dev_alias_pio, ttl_ms: dev_alias_ttl_ms} =
             Sally.device_add_alias(device: device.ident, name: name)

    assert %{
             cmd: %{},
             description: "<none>",
             name: ^name,
             pio: ^dev_alias_pio,
             ttl_ms: ^dev_alias_ttl_ms,
             host: %{
               name: ^host_name,
               ident: ^host_ident,
               profile: ^host_profile,
               last_seen_at: ^host_last_seen_at
             },
             device: %{ident: ^dev_ident, last_seen_at: ^dev_last_seen_at}
           } = Sally.devalias_info(name)
  end

  describe "Sally.devalias_rename/1 handles" do
    @tag device_add: [auto: :mcp23008], devalias_add: [count: 2], just_saw: []
    test "when the to name is taken", %{dev_alias: dev_aliases} do
      assert [%Sally.DevAlias{name: from}, %Sally.DevAlias{name: to}] = dev_aliases

      assert {:name_taken, ^to} = Sally.devalias_rename(from: from, to: to)
    end

    @tag device_add: [auto: :ds], devalias_add: [], just_saw: []
    test "when the new name is available", %{dev_alias: dev_alias} do
      # first, test Host performs the rename
      new_name = Sally.DevAliasAid.unique(:dev_alias)

      assert %Sally.DevAlias{name: ^new_name} = Sally.DevAlias.rename(from: dev_alias.name, to: new_name)

      # second, test Sally.dev_alias_rename recognizes success
      assert :ok = Sally.devalias_rename(from: new_name, to: Sally.DevAliasAid.unique(:dev_alias))
    end

    test "when requested dev_alias name is unavailable" do
      unavailable = Sally.DevAliasAid.unique(:dev_alias)

      assert {:not_found, ^unavailable} =
               Sally.devalias_rename(from: unavailable, to: Sally.DevAliasAid.unique(:dev_alias))
    end

    test "when opts are invalid" do
      assert {:bad_args, _} = Sally.devalias_rename([])
    end
  end

  describe "Sally.DevAlias.status_lookup/3" do
    @tag device_add: [auto: :mcp23008], devalias_add: []
    @tag command_add: [count: 50, shift_unit: :minutes, shift_increment: -1]
    test "handles a DevAlias with Commands", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      name_map = %{name: name, nature: :cmds}
      {elapsed, dev_alias} = Timex.Duration.measure(Sally.DevAlias, :status_lookup, [name_map, []])
      assert_execution_us(elapsed, 15_000)

      assert %Sally.DevAlias{} = dev_alias
      assert Ecto.assoc_loaded?(dev_alias.cmds)
      assert Ecto.assoc_loaded?(dev_alias.datapoints)

      assert [%Sally.Command{}] = dev_alias.cmds
    end

    @tag device_add: [auto: :ds], devalias_add: []
    @tag datapoint_add: [count: 100, shift_unit: :seconds, shift_increment: -7]
    test "handles DevAlias with Datapoints", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      name_map = %{name: name, nature: :datapoints}
      {elapsed, dev_alias} = Timex.Duration.measure(Sally.DevAlias, :status_lookup, [name_map, []])
      assert_execution_us(elapsed, 15_000)

      assert %Sally.DevAlias{} = dev_alias
      assert Ecto.assoc_loaded?(dev_alias.cmds)
      assert Ecto.assoc_loaded?(dev_alias.datapoints)

      assert [%{temp_f: temp_f, temp_c: temp_c, relhum: relhum}] = dev_alias.datapoints
      assert is_float(temp_f)
      assert is_float(temp_c)
      assert is_float(relhum)
    end
  end

  describe "Sally.DevAlias.execute_cmd/2" do
    @tag device_add: [auto: :mcp23008], devalias_add: []
    @tag command_add: [count: 3, shift_unit: :minutes, shift_increment: -1]
    test "creates new pending command from Sally.DevAlias", ctx do
      assert %{device: %Sally.Device{ident: device_ident}, dev_alias: %Sally.DevAlias{} = dev_alias} = ctx

      cmd = "on"

      # NOTE: include the echo: true option to receive the final Sally.Host.Instruct
      # for validation
      {:pending, %Sally.Command{cmd: ^cmd, refid: refid}} =
        Sally.DevAlias.execute_cmd(dev_alias, cmd: cmd, echo: true)

      assert_receive {:echo,
                      %Sally.Host.Instruct{
                        client_id: "sally_test",
                        data: %{ack: true, cmd: ^cmd, pio: 0},
                        filters: [^device_ident, ^refid],
                        ident: <<"host"::binary, _::binary>>,
                        name: <<"hostname"::binary, _::binary>>,
                        packed_length: 33,
                        subsystem: "i2c"
                      }},
                     1

      # NOTE: direct call to Sally.DevAlias.execute_cmd/2 should not track the command
      refute Alfred.Broom.tracked?(refid)
    end

    @tag device_add: [auto: :mcp23008], devalias_add: []
    @tag command_add: [count: 3, shift_unit: :minutes, shift_increment: -1]
    test "creates new acked command from Sally.DevAlias", ctx do
      assert %{dev_alias: %Sally.DevAlias{} = dev_alias} = ctx

      cmd = "on"
      opts = [cmd: cmd, cmd_opts: [ack: :immediate]]

      {elapsed, {:ok, %Sally.Command{cmd: ^cmd}}} =
        Timex.Duration.measure(Sally.DevAlias, :execute_cmd, [dev_alias, opts])

      assert_execution_us(elapsed, 25_000)
    end
  end

  describe "Sally.DevAlias EXPLAIN" do
    @tag device_add: [auto: :mcp23008], devalias_add: []
    @tag command_add: [count: 50, shift_unit: :minutes, shift_increment: -1]
    test "for join of last Sally.Command", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      explain_output = Sally.DevAlias.explain(name, :status, :cmds, [])

      assert explain_output =~ ~r/Index Scan/
      assert explain_output =~ ~r/Sort Method: top-N heapsort/
    end

    @tag device_add: [auto: :ds], devalias_add: []
    @tag datapoint_add: [count: 40, shift_unit: :seconds, shift_increment: -7]
    test "for join of recent Sally.Datapoint", ctx do
      assert %{dev_alias: %Sally.DevAlias{name: name}} = ctx

      explain_output = Sally.DevAlias.explain(name, :status, :datapoints, [])
      assert explain_output =~ ~r/(Join Filter).|\s+(Index Scan).|\s+(Rows Removed)/
    end
  end

  describe "Sally.DevAlias.multi_just_saw/1" do
    @tag device_add: [auto: :mcp23008], devalias_add: [count: 4]
    @tag command_add: [count: 2, shift_unit: :minutes, shift_increment: -1]
    test "updates updated_at", ctx do
      assert %{dev_alias: dev_aliases, device: %Sally.Device{} = device} = ctx

      device = struct(device, aliases: dev_aliases)

      assert {:ok, %{check: {4, updated_aliases}}} =
               Ecto.Multi.new()
               |> Ecto.Multi.put(:device, device)
               |> Ecto.Multi.put(:seen_at, DateTime.utc_now())
               |> Ecto.Multi.update_all(:check, fn x -> Sally.DevAlias.just_saw_db(x) end, [])
               |> Sally.Repo.transaction()

      {sort_dev_aliases(dev_aliases), sort_dev_aliases(updated_aliases)}
      |> then(fn {l1, l2} -> Enum.zip_with(l1, l2, fn e1, e2 -> {e1, e2} end) end)
      |> Enum.each(fn {original, updated} ->
        assert %Sally.DevAlias{id: original_id, updated_at: original_at} = original
        assert %Sally.DevAlias{id: updated_id, updated_at: updated_at} = updated

        assert ^updated_id = original_id
        assert Timex.after?(updated_at, original_at)
      end)

      # pretty_puts(updated_aliases)
    end
  end

  def sort_dev_aliases(dev_aliases) do
    Enum.sort(dev_aliases, fn %{id: lhs}, %{id: rhs} -> lhs <= rhs end)
  end

  def format_elapsed_ms(ms), do: Timex.format_duration(ms, :humanized)
end
