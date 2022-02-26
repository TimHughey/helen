defmodule Betty.MetricTest do
  use ExUnit.Case, async: true

  @moduletag betty: true, betty_metric: true

  describe "Betty.Metric.map/3" do
    test "properly converts and filters fields" do
      data = [boolean: true, float: 1.98737349, integer: 3, binary: "hello", atom: :doctor]

      # NOTE: first argument is the accumulator
      assert %{fields: refined} = Betty.Metric.map(%{}, :fields, %{fields: data})

      assert %{boolean: 1, float: 1.987, integer: 3} = refined
      assert map_size(refined) == 3
    end

    test "properly converts and filters tags" do
      data = [module: __MODULE__, server_name: __MODULE__, binary: "hello", atom: :doctor, integer: 3]

      # NOTE: first argument is the accumulator
      assert %{tags: refined} = Betty.Metric.map(%{}, :tags, %{tags: data})

      mod = Module.split(__MODULE__) |> Enum.join(".")
      assert %{module: ^mod, server_name: ^mod, binary: "hello", atom: "doctor"} = refined
      assert map_size(refined) == 4
    end
  end

  describe "Betty.Metric.write/1" do
    test "raises when measurement is missing" do
      opts = [tags: [hello: :doctor], fields: [float: 1.23]]

      assert_raise(RuntimeError, ~r/measurement/, fn -> Betty.Metric.write(opts) end)
    end

    test "raises when fields or tags are missing" do
      opts = [measurement: "runtime", fields: [float: 1.23]]

      assert_raise(RuntimeError, ~r/tags/, fn -> Betty.Metric.write(opts) end)

      opts = [measurement: "runtime", tags: [module: __MODULE__]]

      assert_raise(RuntimeError, ~r/fields/, fn -> Betty.Metric.write(opts) end)
    end

    test "raises when fields or tags are empty" do
      opts = [measurement: "runtime", tags: [], fields: [float: 1.23]]

      assert_raise(RuntimeError, ~r/tags/, fn -> Betty.Metric.write(opts) end)

      opts = [measurement: "runtime", tags: [module: __MODULE__], fields: []]

      assert_raise(RuntimeError, ~r/fields/, fn -> Betty.Metric.write(opts) end)
    end

    test "writes a metric from well-formed opts" do
      test_tag = Timex.now() |> to_string()
      test_field = :rand.uniform(100_000)

      opts = [measurement: "runtime", tags: [test_tag: test_tag], fields: [test_field: test_field]]

      assert {:ok, point_data} = Betty.Metric.write(opts)
      assert %{measurement: "runtime", tags: tags, fields: fields, timestamp: _} = point_data
      assert %{test_tag: ^test_tag} = tags
      assert %{test_field: ^test_field} = fields

      tag_values = Betty.measurement("runtime", :tag_values)
      assert test_tags = get_in(tag_values, [:test_tag])

      assert Enum.any?(test_tags, &match?({:test_tag, ^test_tag}, &1))
    end
  end
end
