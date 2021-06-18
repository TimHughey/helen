defmodule SallyHostTest do
  @moduledoc false

  ##
  ## Test of basic Device and Alias creation via TestSupport
  ##

  use ExUnit.Case, async: true
  use Should

  @host_ident_default "sally.host000"
  @host_name_default "Sally Host Initial"

  @moduletag db_base: true, sally_host: true

  alias Sally.{Host, Repo}

  setup_all ctx do
    ctx
  end

  setup [:setup_init]

  test "can Host upsert a new record", _ctx do
    create_host()
  end

  @tag host_opts: %{ident: "sally.host001", name: "Sally Upsert Test"}
  test "can Host upsert an existing record", ctx do
    existing = create_host(ctx)
    updated_opts = %{ident: ctx.host_opts.ident, name: "Sally Host Name Changed"}
    updated = create_host(updated_opts)

    fail = pretty("update existing failed", updated)
    assert existing.id == updated.id, fail
    assert existing.ident == updated.ident, fail
    refute existing.name == updated_opts.name, fail
    assert existing.profile == updated.profile, fail
    refute existing.last_start_at == updated.last_start_at
    refute existing.last_seen_at == updated.last_seen_at
  end

  defp create_host(opts \\ %{}) do
    res = opts |> make_host_opts() |> Host.changeset() |> Repo.insert(Host.insert_opts())

    should_be_ok_tuple_with_schema(res, Host)

    elem(res, 1)
  end

  defp make_host_opts(opts) do
    %{
      ident: opts[:host_ident] || @host_ident_default,
      name: opts[:host_name] || @host_name_default,
      sent_at: DateTime.utc_now(),
      data: %{build_date: "Jul 13 1971", build_time: "13:05:00"}
    }
  end

  defp setup_init(ctx) do
    ctx
  end
end
