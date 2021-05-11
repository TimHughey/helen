defmodule AlfredNamesTest do
  use ExUnit.Case
  use AlfredTestShould

  alias Alfred.{KnownName, NamesAgent}
  alias NamesTestHelper, as: Helper

  @moduletag :names_agent

  setup_all ctx do
    ctx
  end

  setup ctx do
    ctx
    |> Helper.make_names()
    |> Helper.make_names_list()
    |> Helper.just_saw()
    |> Helper.random_name()
  end

  @tag names: 10
  test "can Alfred.NamesAgent create a unique sequence of names", ctx do
    should_be_non_empty_list(ctx.names)
  end

  @tag names: 10
  @tag make_names_list: true
  test "can Alfred.NamesAgent create list of name maps", ctx do
    should_be_non_empty_list(ctx.names_list)

    first_name = hd(ctx.names)
    first_entry = hd(ctx.names_list)

    fail = pretty("first entry in names list should be for #{first_name}", ctx.names_list)
    assert first_name == first_entry.name, fail
  end

  @tag names: 10
  @tag just_saw: :auto
  test "can NamesAgent.just saw() add a name list", %{random_name: random_name} do
    res = NamesAgent.get(random_name)

    should_be_struct(res, KnownName)
  end

  @tag names: 10
  @tag just_saw: :auto
  @tag ttl_ms: 5
  test "can NamesAgent.get() prune expired entries", ctx do
    expire = ctx.names |> Enum.at(0)
    not_expire = ctx.names |> Enum.at(1)

    # update one KnownName to a longer ttl
    [%{name: not_expire, ttl_ms: 1000}] |> NamesAgent.just_saw(ctx.module)

    # pass time so ttl expires
    Process.sleep(ctx.ttl_ms + 2)

    res = NamesAgent.get(expire)
    fail = pretty("#{expire} should have expired", res)
    assert is_nil(res), fail

    res = NamesAgent.get(not_expire)
    fail = pretty("#{not_expire} should have not expired", res)
    assert %KnownName{} = res, fail
  end
end