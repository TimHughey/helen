defmodule Sally.HostTest do
  use ExUnit.Case, async: false
  use Sally.TestAid

  @moduletag sally: true, sally_host: true

  setup_all do
    # always create and setup a host
    {:ok, %{host_add: []}}
  end

  setup [:host_add]

  describe "Sally.host_ota_live/1" do
    test "invokes an OTA for live hosts with default opts", %{host: _} do
      assert [%Sally.Host.Instruct{} | _] = Sally.host_ota_live(echo: :instruct)

      assert_receive %Sally.Host.Instruct{
                       data: %{file: <<"00"::binary, _::binary>>, valid_ms: 60_000},
                       filters: ["ota"],
                       ident: <<"host."::binary, _::binary>>,
                       packed_length: 62,
                       subsystem: "host"
                     },
                     1
    end
  end

  test "Sally.host_retire/1 retires an existing host", %{host: host} do
    %Sally.Host{name: retire_name, ident: retire_ident} = host

    assert {:ok, %Sally.Host{authorized: false, ident: ^retire_ident, reset_reason: "retired"}} =
             Sally.host_retire(retire_name)
  end

  describe "Sally.host_rename/1 handles" do
    test "when the to name is taken", %{host: host} do
      # create a second host
      host2 = host_add([])

      taken_name = host2.name
      opts = [from: host.name, to: taken_name]
      assert {:name_taken, ^taken_name} = Sally.host_rename(opts)
    end

    test "when the new name is available", %{host: host} do
      # first, test Host performs the rename
      opts = [from: host.name, to: Sally.HostAid.unique(:name)]
      assert %Sally.Host{} = Sally.Host.rename(opts)

      # second, test Sally.host_rename recognizes success
      opts = [from: opts[:to], to: Sally.HostAid.unique(:name)]
      assert :ok = Sally.host_rename(opts)
    end

    test "when requested host name is unavailable" do
      opts = [from: Sally.HostAid.unique(:name), to: Sally.HostAid.unique(:name)]
      src_name = opts[:from]
      assert {:not_found, ^src_name} = Sally.host_rename(opts)
    end

    test "when opts are invalid" do
      assert {:bad_args, _} = Sally.host_rename([])
    end
  end

  describe "Sally.Host.live/1" do
    test "returns a list of %Host{} with default opts", %{host: _host} do
      assert [%Sally.Host{} | _] = Sally.Host.live()
    end
  end

  describe "Sally.Host profiles" do
    test "current directory" do
      assert true == true
    end
  end
end
