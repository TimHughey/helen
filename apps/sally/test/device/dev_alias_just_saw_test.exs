defmodule Sally.DevAliasJustSawTest do
  use ExUnit.Case, async: true
  use Should
  use Sally.TestAids

  @moduletag sally: true, sally_dev_alias_just_saw: true

  alias Ecto.Multi
  alias Sally.{DevAlias, DeviceAid, HostAid}
  alias Sally.Repo

  setup_all do
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup, :device_add, :devalias_add, :devalias_just_saw]

  defmacro validate_db_result(db_result, seen_at, count) do
    quote location: :keep, bind_quoted: [db_result: db_result, seen_at: seen_at, count: count] do
      results = Should.Be.Tuple.with_rc(db_result, :ok)

      map = Should.Be.Map.with_keys(results, [:seen_list])
      seen_list = Should.Be.List.with_length(map.seen_list, count)

      for dev_alias <- seen_list do
        Should.Be.Schema.named(dev_alias, DevAlias)
        Should.Be.match(dev_alias.updated_at, seen_at)
      end
    end
  end

  describe "Sally.DevAlias.just_saw/3" do
    @tag device_add: [], devalias_add: []
    test "handles a single DevAlias in an Ecto.Multi pipeline", ctx do
      seen_at = Timex.now()

      db_result =
        Multi.new()
        |> Multi.put(:aliases, [ctx.dev_alias])
        |> Multi.run(:seen_list, DevAlias, :just_saw, [seen_at])
        |> Repo.transaction()

      validate_db_result(db_result, seen_at, 1)
    end

    @tag device_add: [auto: :mcp23008], devalias_add: [count: 5]
    test "handles multiple DevAlias in an Ecto.Multi pipeline", ctx do
      seen_at = Timex.now()
      dev_aliases = ctx.dev_alias
      expected_count = length(dev_aliases)

      db_result =
        Multi.new()
        |> Multi.put(:aliases, dev_aliases)
        |> Multi.run(:seen_list, DevAlias, :just_saw, [seen_at])
        |> Repo.transaction()

      validate_db_result(db_result, seen_at, expected_count)
    end
  end

  describe "Sally.DevAlias.just_saw/4" do
    @tag device_add: [auto: :mcp23008], devalias_add: [count: 8]
    test "handles a single DevAlias id in an Ecto.Multi pipeline", ctx do
      dev_alias = DevAliasAid.random_pick(ctx.dev_alias, 1)
      seen_at = Timex.now()

      db_result =
        Multi.new()
        |> Multi.run(:seen_list, DevAlias, :just_saw_id, [dev_alias.id, seen_at])
        |> Repo.transaction()

      validate_db_result(db_result, seen_at, 1)
    end
  end
end
