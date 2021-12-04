defmodule BettyTest do
  use ExUnit.Case, async: true
  use Should

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
      Application.get_env(:betty, Betty.Connection)
      |> Should.Be.NonEmpty.list()
      |> Should.Contain.keys([:auth])
    end

    test "pings the database", _ctx do
      Should.Be.asserted(fn -> :pong == Betty.Connection.ping() end)
    end
  end

  describe "Betty schema exploration" do
    test "measurement/2 returns a list of tags" do
      Betty.measurement(:app_error, :tags)
      |> Should.Be.NonEmpty.list()
    end

    test "measurement/2 returns a list of fields" do
      Betty.measurement(:betty_test, :fields)
      |> Should.Be.NonEmpty.list()
      |> Should.Contain.keys([:val1, :val2])
    end

    test "measurement/2 returns a list of all tags and values" do
      Betty.measurement(:betty_test, :tag_values)
      |> Should.Be.NonEmpty.list()
      |> Should.Contain.keys([:test_tag])
    end

    test "measurement/2 returns a list of values of a single tag" do
      Betty.measurement(:app_error, :tag_values, want: [:module])
      |> Should.Be.NonEmpty.list()
    end

    test "measurement/2 returns a list of values of multiple tags" do
      want_tags = [:rc, :module]

      Betty.measurement(:app_error, :tag_values, want: want_tags)
      |> Should.Be.NonEmpty.list()
      |> Should.Contain.keys(want_tags)
    end

    test "measurements/0 returns list of known measurements" do
      Betty.measurements()
      |> Should.Be.NonEmpty.list()
    end
  end

  describe "Betty database maintenance: " do
    test "retrieve all shards" do
      res = Betty.shards("helen_test")

      Should.Be.Map.with_keys(res, [:columns, :name, :values])
      Should.Be.NonEmpty.list(res.columns)
      Should.Be.NonEmpty.list(res.values)
      Should.Be.binary(res.name)
    end

    @tag skip: true
    test "drop all measurements" do
      Betty.measurements(:drop_all) |> Should.Be.NonEmpty.list()
    end
  end

  describe "Betty.app_error_v2/2" do
    test "handles a well-formed tags list" do
      tags = [module: __MODULE__, rc: :error]
      rc = Betty.app_error_v2(tags, return: :rc)

      Should.Be.asserted(fn -> rc == :error end)
    end
  end

  describe "Betty.runtime_metric/3" do
    test "writes a metric with tags and fields" do
      rc = Betty.runtime_metric(__MODULE__, [name: "test"], val: 1)
      Should.Be.asserted(fn -> rc == __MODULE__ end)
    end
  end

  describe "Betty.write/1" do
    test "handles well-formed opts" do
      [
        measurement: "betty_test",
        fields: [val1: true, val2: 100.1, val3: false],
        tags: %{test_tag: false, module: __MODULE__, test_tag2: true, test_tag3: nil}
      ]
      |> Betty.write()
      |> Should.Be.ok()
    end

    test "handles well-formed opts with :return" do
      [
        return: [],
        measurement: "betty_test",
        fields: [val1: true, val2: 100.1],
        tags: %{test_tag: true, module: __MODULE__, cmd: "on"}
      ]
      |> Betty.write()
      |> Should.Be.list()
    end

    test "handles missing opts" do
      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          [
            fields: [val1: true, val2: 100.1],
            tags: %{test_tag: true, module: __MODULE__}
          ]
          |> Betty.write()
          |> Should.Be.ok()
        end)

      Should.Contain.binaries(log, "missing")
    end
  end

  describe "Betty.app_error/2" do
    @tag capture_log: true
    test "detects and logs invalid args" do
      rc = Betty.app_error(nil, [])

      Should.Be.asserted(fn -> is_nil(rc) end)
    end
  end
end
