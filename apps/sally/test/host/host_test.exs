defmodule Sally.HostTest do
  use ExUnit.Case, async: false
  use Sally.TestAid

  @moduletag sally: true, sally_host: true

  setup [:host_add]

  describe "Sally.Host.authorize/2" do
    @tag host_add: []
    test "removes authorizaton", ctx do
      assert %{host: %{authorized: true} = host} = ctx

      host = Sally.Host.deauthorize(host)
      assert %Sally.Host{authorized: false} = host
    end

    @tag host_add: [setup: false]
    test "adds authorizaton", ctx do
      assert %{host: %{authorized: false} = host} = ctx

      host = Sally.Host.authorize(host, true)
      assert %Sally.Host{authorized: true} = host
    end
  end

  describe "Sally.Host.begins_with/2" do
    @tag host_add: []
    test "returns idents matching pattern", ctx do
      assert %{host: %{ident: <<_::binary>> = what}} = ctx

      prefix = binary_part(what, 0, 2)

      found = Sally.Host.begins_with(prefix)

      assert [<<_::binary>> | _] = found

      # query = Sally.Host.begins_with_query(prefix, :ident)
      # raw = Sally.Repo.explain(:all, query, analyze: true, buffers: true, wal: true)
      #
      # ["\n", raw] |> IO.puts()
    end

    @tag host_add: []
    test "returns names matching pattern", ctx do
      assert %{host: %{name: <<_::binary>> = what}} = ctx

      prefix = binary_part(what, 0, 2)

      found = Sally.Host.begins_with(prefix, :name)

      assert [<<_::binary>> | _] = found

      # query = Sally.Host.begins_with_query(prefix, :name)
      # raw = Sally.Repo.explain(:all, query, analyze: true, buffers: true, wal: true)
      #
      # ["\n", raw] |> IO.puts()
    end
  end

  describe "Sally.Host.boot_payload/1" do
    test "returns cleaned map for known profile" do
      profile = "pwm"

      map = Sally.Host.boot_payload(%{profile: profile})

      assert %{"host" => %{}, "meta" => %{}, "pwm" => %{}} = map
    end

    test "raises when profile not found" do
      host_sim = %{profile: "unknown"}
      assert_raise(RuntimeError, ~r/enoent/, fn -> Sally.Host.boot_payload(host_sim) end)
    end
  end

  describe "Sally.Host.latest/1" do
    @tag host_add: [setup: false]
    test "finds latest (default opts)", ctx do
      assert %{host: host} = ctx
      assert %{authorized: false, ident: want_ident, name: want_ident} = host

      # query = Sally.Host.latest_query([])
      # explain = Sally.DevAlias.Explain.explain(query, [])
      # Sally.DevAlias.Explain.assemble_output(explain, __MODULE__, " test") |> IO.puts()

      # NOTE: default opts return ident
      latest = Sally.Host.latest(multiple: true, schema: true)

      case latest do
        [_ | _] = many ->
          assert Enum.any?(many, &match?(%{ident: ^want_ident}, &1))

        %{ident: got_ident} ->
          assert got_ident == want_ident

        other ->
          refute other == latest
      end

      # NOTE: retire the found hosts to prevent interaction with other time based tests
      assert :ok = List.wrap(latest) |> Enum.each(&Sally.Host.retire(&1))
    end

    test "returns empty list when no latest found" do
      opts = [ref_dt: Timex.now() |> Timex.shift(years: 20)]
      assert [] == Sally.Host.latest(opts)
    end
  end

  describe "Sally.Host.live/1" do
    @tag host_add: []
    test "returns a list of schemas (default opts)", ctx do
      assert %{host: _host} = ctx
      live_hosts = Sally.Host.live([])

      refute [] == live_hosts

      assert Enum.all?(live_hosts, &match?(%Sally.Host{}, &1))
    end

    test "returns empty list (custom opts)" do
      # set ref_dt FAR in the FUTURE to ensure no live hosts are found
      opts = [ref_dt: Timex.now() |> Timex.shift(years: 20), minutes: -10]

      live_hosts = Sally.Host.live(opts)
      assert [] == live_hosts
    end
  end

  describe "Sally.Host.ota/2" do
    @tag host_add: []
    test "sends ota instruction for known host (default opts)", ctx do
      assert %{host: %{ident: ident} = host} = ctx

      ota_host = Sally.Host.ota(host, seconds: -1)
      assert %Sally.Host{instruct: instruct} = ota_host

      assert %Sally.Host.Instruct{ident: ^ident} = instruct
    end
  end

  describe "Sally.Host.profile/2" do
    @tag host_add: []
    test "sets profile when profile exists", ctx do
      assert %{host: %{authorized: true, profile: prev_profile} = host} = ctx

      profile = "lightdesk"

      assert {:ok, %{profile: new_profile}} = Sally.Host.profile(host, profile)
      refute new_profile == prev_profile
      assert new_profile == profile
    end

    @tag host_add: []
    test "properly handles unknown profile", ctx do
      assert %{host: %{authorized: true} = host} = ctx

      profile = "unknown"

      error = Sally.Host.profile(host, profile)
      # NOTE: actual error message checked in Sally.Host.setup/2 test
      assert {:error, %Ecto.Changeset{} = changeset} = error

      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        assert msg =~ ~r/profile/
        assert [additional: <<"unable"::binary, _::binary>>] = opts
      end)
    end
  end

  describe "Sally.Host.rename/2" do
    @tag host_add: []
    test "handles new name available", ctx do
      %{host: %Sally.Host{id: id} = host} = ctx
      # create unique new name
      to = Sally.HostAid.unique(:name)

      assert %{id: ^id, name: ^to} = Sally.Host.rename(host, to)
    end

    @tag host_add: []
    test "handles new name taken", ctx do
      %{host: %Sally.Host{} = host} = ctx
      # create a second host
      assert %{name: taken_name} = host_add([])
      assert {:name_taken, ^taken_name} = Sally.Host.rename(host, taken_name)
    end
  end

  describe "Sally.Host.restart/1" do
    @tag host_add: []
    test "sends restart instruction", ctx do
      %{host: %{} = host} = ctx

      restart_host = Sally.Host.restart(host, echo: :instruct)
      assert %Sally.Host{instruct: instruct} = restart_host
      assert %Sally.Host.Instruct{filters: ["restart"]} = instruct

      assert_receive(%Sally.Host.Instruct{filters: ["restart"]}, 10)
    end
  end

  describe "Sally.Host.setup/2" do
    @tag host_add: [setup: false]
    test "detects unknown profile", ctx do
      assert %{host: %{authorized: false} = host} = ctx

      error = Sally.Host.setup(host, profile: "unknown")

      # NOTE: actual error messages are checked in Sally.Host.profile/2 tests
      assert {:error, %Ecto.Changeset{}} = error
    end

    @tag host_add: [setup: false]
    test "sets up host with known profile", ctx do
      assert %{host: %{authorized: false} = host} = ctx

      profile = "pwm"
      assert {:ok, host} = Sally.Host.setup(host, profile: profile)

      assert %Sally.Host{authorized: true, profile: ^profile} = host
    end
  end

  describe "Sally.Host.unnamed/1" do
    @tag host_add: [setup: false]
    test "finds all unnamed hosts (default opts)", ctx do
      assert %{host: host} = ctx
      assert %{authorized: false, ident: want_ident, name: want_ident} = host

      # query = Sally.Host.unnamed_query([])
      # explain = Sally.DevAlias.Explain.explain(query, [])
      # Sally.DevAlias.Explain.assemble_output(explain, __MODULE__, " test") |> IO.puts()

      # NOTE: returns list of Sally.Host
      unnamed = Sally.Host.unnamed([])

      assert Enum.all?(unnamed, &match?(%{ident: ident, name: ident}, &1))
      assert Enum.any?(unnamed, &match?(%{ident: ^want_ident}, &1))

      Sally.Host.retire(host)
    end

    test "returns empty list when no unnamed found" do
      opts = [ref_dt: Timex.now() |> Timex.shift(years: 20)]
      assert [] == Sally.Host.latest(opts)
    end
  end
end
