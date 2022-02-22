defmodule Sally.Config.Test do
  use ExUnit.Case, async: true
  use Sally.TestAid

  @moduletag sally: true, sally_configt: true

  describe "Sally.Config starts" do
    test "supervised and loads config for app" do
      mod = Sally.Config

      assert pid = GenServer.whereis(mod)
      assert Process.alive?(pid)

      raw_state = :sys.get_state(mod)
      assert %{config: %{} = config, cache: %{} = cache} = raw_state
      assert %{__MODULE__ => all} = config
      key1 = get_in(all, [:key1])
      assert [hello: :doctor, yesterday: :tomorrow] = key1
      assert %{paths: %{}} = cache
    end

    test "unsupervised with specified opts, does not load app config" do
      opts = [name: __MODULE__, hello: :doctor]
      assert {:ok, pid} = Sally.Config.start_link(opts)
      assert Process.alive?(pid)

      assert pid = GenServer.whereis(__MODULE__)

      state = :sys.get_state(pid)

      assert %{config: %{hello: :doctor}, cache: %{paths: %{}}} = state
      refute get_in(state, [:config, __MODULE__, :key1])
    end
  end

  describe "Sally.Config.file_locate/2" do
    test "handles path not found" do
      what = {__MODULE__, :path_error}
      assert {:error, :no_path} = Sally.Config.file_locate(what, [])
    end

    test "returns tuple of path and list of files (default opts)" do
      what = {__MODULE__, :firmware}

      assert {<<_::binary>> = path, [_ | _] = files} = Sally.Config.file_locate(what)
      assert path =~ ~r/firmware/
      assert Enum.all?(files, &Regex.match?(~r/ruth/, &1))
    end

    test "return most recent file found at path" do
      what = {__MODULE__, :firmware}
      latest = Sally.Config.file_locate(what, want: :latest)

      assert <<"00.02"::binary, _::binary>> = latest
    end
  end

  describe "Sally.Config.get_in" do
    test "gets the config value using specified path (no default)" do
      assert :doctor = Sally.Config.get_via_path([__MODULE__, :key1, :hello])
    end

    test "returns nil when specified path does not contain a value (no default)" do
      refute Sally.Config.get_via_path([__MODULE__, :unknown, :hello])
    end

    test "returns default when specified path does not contain a value" do
      assert :default = Sally.Config.get_via_path([__MODULE__, :unknown, :hello], :default)
    end
  end

  describe "Sally.Config.path_get/1" do
    test "returns :none when {mod, dir} unavailable" do
      assert :none == Sally.Config.path_get({__MODULE__, :not_a_key})
    end

    test "returns binary when {mod, dir} are available" do
      chk_map = Sally.Config.path_get({__MODULE__, :profiles}, chk_map: true)
      assert %{found: <<_::binary>> = profile_path} = chk_map

      assert %{cache_hit: :no, paths: paths, stat: stat} = chk_map
      assert %{{__MODULE__, :profiles} => ^profile_path} = paths
      assert {:ok, %File.Stat{}} = stat

      # NOTE: when a cached value is found the reduction is halted and value is returned
      # so we expect a binary returned when return_chk_map: true
      profile_check = Sally.Config.path_get({__MODULE__, :profiles}, chk_map: true)

      assert profile_check == profile_path
    end

    test "handles absolute paths" do
      path = Sally.Config.path_get({__MODULE__, :tmp})
      assert <<"/tmp"::binary>> = path
    end
  end
end
