defmodule Sally.DevAliasJustSawTest do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_dev_alias_just_saw: true

  setup_all do
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :devalias_just_saw]

  defmacro validate_db_result(db_result, seen_at, count) do
    quote bind_quoted: [db_result: db_result, seen_at: seen_at, count: count] do
      assert {:ok, %{seen_list: seen_list}} = db_result

      assert length(seen_list) == count

      Enum.all?(seen_list, fn dev_alias -> assert %Sally.DevAlias{updated_at: ^seen_at} = dev_alias end)
    end
  end

  describe "Sally.DevAlias.just_saw/3" do
    @tag device_add: [], devalias_add: []
    test "handles a single DevAlias in an Ecto.Multi pipeline", ctx do
      seen_at = Timex.now()

      db_result =
        Ecto.Multi.new()
        |> Ecto.Multi.put(:aliases, [ctx.dev_alias])
        |> Ecto.Multi.run(:seen_list, Sally.DevAlias, :just_saw, [seen_at])
        |> Sally.Repo.transaction()

      validate_db_result(db_result, seen_at, 1)
    end

    @tag device_add: [auto: :mcp23008], devalias_add: [count: 5]
    test "handles multiple DevAlias in an Ecto.Multi pipeline", ctx do
      seen_at = Timex.now()
      dev_aliases = ctx.dev_alias
      expected_count = length(dev_aliases)

      db_result =
        Ecto.Multi.new()
        |> Ecto.Multi.put(:aliases, dev_aliases)
        |> Ecto.Multi.run(:seen_list, Sally.DevAlias, :just_saw, [seen_at])
        |> Sally.Repo.transaction()

      validate_db_result(db_result, seen_at, expected_count)
    end
  end

  describe "Sally.DevAlias.just_saw/4" do
    @tag device_add: [auto: :mcp23008], devalias_add: [count: 8]
    test "handles a single DevAlias id in an Ecto.Multi pipeline", ctx do
      dev_alias = Sally.DevAliasAid.random_pick(ctx.dev_alias, 1)
      seen_at = Timex.now()

      db_result =
        Ecto.Multi.new()
        |> Ecto.Multi.run(:seen_list, Sally.DevAlias, :just_saw_id, [dev_alias.id, seen_at])
        |> Sally.Repo.transaction()

      validate_db_result(db_result, seen_at, 1)
    end
  end
end
