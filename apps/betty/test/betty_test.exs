defmodule BettyTest do
  use ExUnit.Case, async: true

  @moduletag betty: true

  setup_all do
    on_exit(fn ->
      nil
      #  Betty.measurement(:runtime, :tag_values) |> pretty_puts()
      # Betty.measurements(:drop_all)
    end)

    :ok
  end

  describe "Betty top-level" do
    test "retrieves the connection configuration", _ctx do
      assert [{:auth, _}, {:database, _}, {:host, _} | _] =
               Application.get_env(:betty, Betty.Connection) |> Enum.sort()
    end

    test "pings the database", _ctx do
      assert :pong = Betty.Connection.ping()
    end
  end

  describe "Betty schema exploration" do
    test "measurement/2 returns a list of tags" do
      [_ | _] = tags = Betty.measurement(:app_error, :tags)

      want_tags = [:ack_fail, :align_status, :cmd]
      Enum.each(want_tags, fn tag -> assert tag in tags end)
    end

    test "measurement/2 returns a list of fields" do
      assert [{:val1, _}, {:val2, _} | _] = Betty.measurement(:betty_test, :fields)
    end

    test "measurement/2 returns a list of all tags and values" do
      assert [{:cmd, _} | _] = Betty.measurement(:betty_test, :tag_values)
    end

    test "measurement/2 returns a list of values of a single tag" do
      assert [val1, val2 | _] = Betty.measurement(:app_error, :tag_values, want: [:module])
      assert is_atom(val1)
      assert is_atom(val2)
    end

    test "measurement/2 returns a list of values of multiple tags" do
      assert [{:module, [_ | _]}, {:rc, [_ | _]} | _] =
               Betty.measurement(:app_error, :tag_values, want: [:rc, :module])
    end

    test "measurements/0 returns list of known measurements" do
      assert [:app_error, :betty_test | _] = Betty.measurements()
    end
  end

  describe "Betty database maintenance: " do
    test "retrieve all shards" do
      assert %{columns: [_ | _], name: <<_::binary>>, values: [_ | _]} = Betty.shards("helen_test")
    end

    @tag skip: true
    test "drop all measurements" do
      assert [_ | _] = Betty.measurements(:drop_all)
    end
  end

  describe "Betty.app_error_v2/2" do
    test "handles a well-formed tags list" do
      tags = [module: __MODULE__, rc: :error]
      assert :error = Betty.app_error_v2(tags, return: :rc)
    end
  end

  describe "Betty.runtime_metric/3" do
    test "writes a metric with tags and fields" do
      assert __MODULE__ = Betty.runtime_metric(__MODULE__, [name: "test"], val: 1)
    end
  end

  describe "Betty.write/1" do
    test "handles well-formed opts" do
      assert :ok =
               [
                 measurement: "betty_test",
                 fields: [val1: true, val2: 100.1, val3: false],
                 tags: %{test_tag: false, module: __MODULE__, test_tag2: true, test_tag3: nil}
               ]
               |> Betty.write()
    end

    test "handles well-formed opts with :return" do
      assert [:test] =
               [
                 return: [:test],
                 measurement: "betty_test",
                 fields: [val1: true, val2: 100.1],
                 tags: %{test_tag: true, module: __MODULE__, cmd: "on"}
               ]
               |> Betty.write()
    end

    test "handles missing opts" do
      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          assert :ok =
                   [
                     fields: [val1: true, val2: 100.1],
                     tags: %{test_tag: true, module: __MODULE__}
                   ]
                   |> Betty.write()
        end)

      assert log =~ ~r/missing/
    end
  end

  describe "Betty.app_error/2" do
    @tag capture_log: true
    test "detects and logs invalid args" do
      assert nil === Betty.app_error(nil, [])
    end
  end
end
