defmodule SallyDevAliasAlignTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_dev_alias_align: true

  setup [:dev_alias_add]

  describe "Sally.DevAlias.align_status/1" do
    @tag dev_alias_add: [auto: :pwm, count: 3, cmds: [history: 1]]
    test "makes no change when the reported cmd is the same as local cmd", ctx do
      assert %{device: %Sally.Device{} = device, dev_alias: [_ | _] = dev_aliases} = ctx

      data = %{pins: Sally.CommandAid.make_pins(device, %{pins: [:from_status]})}
      dispatch = %{data: data, sent_at: Timex.now()}
      sim_multi_changes = %{aliases: dev_aliases, dispatch: dispatch}

      multi = Sally.DevAlias.align_status(sim_multi_changes)

      # NOTE: empty txn results signals no changes
      assert {:ok, %{} = changes} = Sally.Repo.transaction(multi)
      assert map_size(changes) == 0
    end

    @tag dev_alias_add: [auto: :pwm, count: 3, cmds: [history: 1, cmd_latest: :pending]]
    test "does nothing when Sally.DevAlias has a pending command", ctx do
      assert %{device: %Sally.Device{} = device, dev_alias: [_ | _] = dev_aliases} = ctx

      # NOTE: Sally.CommandAid.make_pins/2 creates a random pin cmd when a Sally.Command is pending
      pins = Sally.CommandAid.make_pins(device, %{pins: [:from_status]})
      dispatch = %{data: %{pins: pins}, sent_at: Timex.now()}
      sim_multi_changes = %{aliases: dev_aliases, dispatch: dispatch}

      multi = Sally.DevAlias.align_status(sim_multi_changes)

      # NOTE: empty txn results signals no changes
      assert {:ok, changes} = Sally.Repo.transaction(multi)
      assert map_size(changes) == 0
    end

    @tag dev_alias_add: [auto: :pwm, count: 3]
    test "handles Sally.DevAlias without cmd history", ctx do
      assert %{device: %Sally.Device{} = device, dev_alias: [_ | _] = dev_aliases} = ctx

      data = %{pins: Sally.CommandAid.make_pins(device, %{pins: [:random]})}
      dispatch = %{data: data, sent_at: Timex.now()}
      sim_multi_changes = %{aliases: dev_aliases, dispatch: dispatch}

      # multi = Sally.DevAlias.align_status(sim_multi_changes)
      #
      # # NOTE: empty txn results signals no changes
      # assert {:ok, result} = Sally.Repo.transaction(multi)
      # result |> tap(fn x -> ["\n", inspect(x, pretty: true)] |> IO.warn() end)

      assert %Ecto.Multi{} = multi = Sally.DevAlias.align_status(sim_multi_changes)
      assert {:ok, txn} = Sally.Repo.transaction(multi)

      Enum.each(txn, fn {key, val} ->
        # NOTE: multi change "name" (aka map key)
        assert {:aligned, <<_::binary>> = dev_alias_name, pio} = key

        # NOTE: multi change value
        assert %Sally.Command{acked: true, dev_alias_id: dev_alias_id} = val

        # NOTE: validate the original dev aliases were aligned
        assert Enum.find(dev_aliases, &match?(%{name: ^dev_alias_name, id: ^dev_alias_id, pio: ^pio}, &1))
      end)
    end

    @tag dev_alias_add: [auto: :pwm, count: 3, cmds: [history: 1]]
    test "corrects cmd mismatch", ctx do
      assert %{device: %Sally.Device{} = device, dev_alias: [_ | _] = dev_aliases} = ctx

      data = %{pins: Sally.CommandAid.make_pins(device, %{pins: [:random]})}
      dispatch = %{data: data, sent_at: Timex.now()}
      sim_multi_changes = %{aliases: dev_aliases, dispatch: dispatch}

      assert %Ecto.Multi{} = multi = Sally.DevAlias.align_status(sim_multi_changes)
      assert {:ok, txn} = Sally.Repo.transaction(multi)

      Enum.each(txn, fn {key, val} ->
        # NOTE: multi change "name" (aka map key)
        assert {:aligned, <<_::binary>> = dev_alias_name, pio} = key

        # NOTE: multi change value
        assert %Sally.Command{acked: true, dev_alias_id: dev_alias_id} = val

        # NOTE: validate the original dev aliases were aligned
        assert Enum.find(dev_aliases, &match?(%{name: ^dev_alias_name, id: ^dev_alias_id, pio: ^pio}, &1))
      end)
    end
  end
end
