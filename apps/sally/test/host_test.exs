defmodule Sally.HostTest do
  # NOTE:  don't use async: true due to testing Sally.host_setup(:unnamed)
  use ExUnit.Case
  use Should

  alias Sally.{Host, Repo}

  @moduletag db_test: true, sally_host: true

  setup [:host_create, :host_setup]

  @tag host_create: :auto
  @tag host_setup: :auto
  test "Sally.host_retire/1 retires an existing host", %{host: host} do
    res = Sally.host_retire(host.name)
    should_be_ok_tuple_with_struct(res, Host)
    {:ok, retired_host} = res

    to_match = %{authorized: false, reset_reason: "retired", name: host.ident}
    should_be_match(retired_host, to_match)
  end

  describe "Sally.host_rename/1 handles" do
    setup [:host_create, :host_setup]

    @tag host_create: :auto
    @tag host_setup: :auto
    test "when the to name is taken", %{host: host1} do
      # create a second host for name taken test
      %{host: host2} = host_create(%{host_create: :auto, host_setup: :auto}) |> host_setup()

      opts = [from: host1.name, to: host2.name]
      res = Sally.host_rename(opts)

      should_be_tuple_with_rc_and_val(res, :name_taken, host2.name)
    end

    @tag host_create: :auto
    @tag host_setup: :auto
    test "when the new name is available", %{host: host1} do
      # first, test Host performs the rename
      opts = [from: host1.name, to: make_host_name()]
      res = Host.rename(opts)

      should_be_struct(res, Host)

      # second, test Sally.host_rename recognizes success
      opts = [from: opts[:to], to: make_host_name()]
      res = Sally.host_rename(opts)

      should_be_simple_ok(res)
    end

    test "when requested host name is unavailable" do
      # first, test Host performs the rename
      opts = [from: make_host_name(), to: make_host_name()]
      res = Sally.host_rename(opts)

      should_be_not_found_tuple_with_binary(res, opts[:from])
    end

    test "when opts are invalid" do
      # first, test Host performs the rename

      res = Sally.host_rename([])

      should_be_tuple_with_rc_and_val(res, :bad_args, [])
    end
  end

  def host_create(%{host_create: :auto} = ctx) do
    ident = make_ident()
    start_at = DateTime.utc_now()
    seen_at = Timex.shift(start_at, microseconds: 10)

    changes = %{
      ident: ident,
      name: ident,
      last_start_at: start_at,
      last_seen_at: seen_at,
      reset_reason: "power on"
    }

    res =
      Host.changeset(%Host{}, changes, Map.keys(changes))
      |> Repo.insert(Host.insert_opts())

    should_be_ok_tuple_with_struct(res, Host)
    {:ok, new_host} = res

    Map.put(ctx, :host, new_host)
  end

  def host_create(ctx), do: ctx

  def host_setup(%{host_setup: :auto, host: host} = ctx) do
    name = make_host_name()
    res = Sally.host_setup(host.ident, name: name)

    should_be_ok_tuple_with_struct(res, Host)
    {:ok, updated_host} = res

    should_be_equal(updated_host.authorized, true)
    should_be_equal(updated_host.name, name)
    should_be_equal(updated_host.profile, host.profile)

    Map.put(ctx, :host, updated_host)
  end

  def host_setup(ctx), do: ctx

  defp make_host_name, do: "host test #{unique()}"
  defp make_ident, do: "test.#{unique()}"

  defp unique do
    Ecto.UUID.generate() |> String.split("-") |> Enum.at(4)
  end
end
