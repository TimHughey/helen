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

  describe "Betty.app_error/1" do
    test "handles a well-formed tags list" do
      tags = [module: __MODULE__]
      assert {:ok, points} = Betty.app_error(tags)

      mod = inspect(__MODULE__)
      assert %{measurement: "app_error", tags: %{module: ^mod}, fields: %{error: 1}} = points
    end
  end
end
