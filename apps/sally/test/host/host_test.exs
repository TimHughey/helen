defmodule Sally.HostTest do
  # NOTE:  don't use async: true due to testing Sally.host_setup(:unnamed)
  use ExUnit.Case
  use Should
  use Sally.TestAids

  alias Sally.Host

  @moduletag sally: true, sally_host: true

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: [], host_setup: []}}
  end

  setup [:host_add, :host_setup]

  test "Sally.host_retire/1 retires an existing host", %{host: host} do
    host = Sally.host_retire(host.name) |> Should.Be.Ok.tuple_with_struct(Host)

    want_kv = [authorized: false, reset_reason: "retired", name: host.ident]
    Should.Be.Struct.with_all_key_value(host, Host, want_kv)
  end

  describe "Sally.host_rename/1 handles" do
    test "when the to name is taken", %{host: host} do
      # create a second host
      %{host: host2} = host_add(%{host_add: [], host_setup: []})

      opts = [from: host.name, to: host2.name]
      Sally.host_rename(opts) |> Should.Be.Tuple.with_rc_and_binaries(:name_taken, host2.name)
    end

    test "when the new name is available", %{host: host} do
      # first, test Host performs the rename
      opts = [from: host.name, to: HostAid.unique(:name)]
      Host.rename(opts) |> Should.Be.struct(Host)

      # second, test Sally.host_rename recognizes success
      opts = [from: opts[:to], to: HostAid.unique(:name)]
      Sally.host_rename(opts) |> Should.Be.match(:ok)
    end

    test "when requested host name is unavailable" do
      opts = [from: HostAid.unique(:name), to: HostAid.unique(:name)]
      Sally.host_rename(opts) |> Should.Be.Tuple.with_rc_and_binaries(:not_found, opts[:from])
    end

    test "when opts are invalid" do
      Sally.host_rename([]) |> Should.Be.Tuple.with_rc(:bad_args)
    end
  end
end
