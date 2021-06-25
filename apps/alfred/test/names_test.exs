defmodule AlfredNamesTest do
  use ExUnit.Case
  use Should

  # alias Alfred.{KnownName, Names}

  @moduletag :names_agent

  # setup_all ctx do
  #   ctx
  # end
  #
  # test "can Alfred Names Server ", ctx do
  #   should_be_non_empty_list(ctx.names)
  # end

  # @tag make_names: 10
  # @tag make_seen: true
  # test "can Alfred.NamesAgent create list of name maps", ctx do
  #   should_be_non_empty_list(ctx.seen_list)
  #
  #   first_name = hd(ctx.names)
  #   first_entry = hd(ctx.seen_list)
  #
  #   fail = pretty("first entry in names list should be for #{first_name}", ctx.seen_list)
  #   assert first_name == first_entry.name, fail
  # end
  #
  # @tag make_names: 10
  # @tag just_saw: :auto
  # test "can NamesAgent.just saw() add a name list", %{random_name: random_name} do
  #   res = NamesAgent.get(random_name)
  #
  #   should_be_struct(res, KnownName)
  # end
  #
  # @tag make_names: 10
  # @tag just_saw: :auto
  # @tag ttl_ms: 5
  # test "can NamesAgent.get() prune expired entries", ctx do
  #   expire = ctx.names |> Enum.at(0)
  #   not_expire = ctx.names |> Enum.at(1)
  #
  #   # update one KnownName to a longer ttl
  #   res = [%{name: not_expire, ttl_ms: 1000, callback_mod: ctx.module}] |> NamesAgent.just_saw()
  #   should_be_ok_tuple(res)
  #
  #   {:ok, seen_names} = res
  #   should_be_non_empty_list(seen_names)
  #
  #   # pass time so ttl expires
  #   Process.sleep(ctx.ttl_ms + 2)
  #
  #   res = NamesAgent.get(expire)
  #   fail = pretty("#{expire} should have expired", res)
  #   assert res.pruned, fail
  #
  #   res = NamesAgent.get(not_expire)
  #   fail = pretty("#{not_expire} should have not expired", res)
  #   assert %KnownName{} = res, fail
  # end
  #
  # @tag make_names: 10
  # @tag just_saw: :auto
  # @tag ttl_ms: 5
  # test "can NamesAgent.get() return a list of all known names", _ctx do
  #   all = NamesAgent.known()
  #   should_be_non_empty_list(all)
  #
  #   first_known = hd(all)
  #   should_be_struct(first_known, KnownName)
  # end
end
