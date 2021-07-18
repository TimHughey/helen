defmodule BettyTest do
  use ExUnit.Case, async: true

  test "can Betty retrieve the connection configuration", _ctx do
    cfg = Application.get_env(:betty, Betty.Connection)
    refute cfg == [], "configuration should be a list: #{inspect(cfg)}"

    auth = cfg[:auth]
    auth_keys? = auth[:username] && auth[:password]

    fail = "configuration should include auth: [username: _, password: _]: #{inspect(auth)}"
    assert auth_keys?, fail
  end

  test "can Betty retrieve all shards" do
    res = Betty.shards("helen_test")

    assert %{columns: cols, name: name, values: values} = res
    refute cols == [], "columns should be non-empty list: #{inspect(res, pretty: true)}"
    assert name == "helen_test", "name should be test database: #{inspect(res, pretty: true)}"
    refute values == [], "values should be non-empty list: #{inspect(res, pretty: true)}"
  end

  test "can Betty retrieve available measurements" do
    res = Betty.measurements()

    refute res == [], "should be non-empty list: #{inspect(res, pretty: true)}"
  end

  test "can Betty ping the database", _ctx do
    assert :pong == Betty.Connection.ping()
  end

  test "can Betty write a %Metric{} to the database", _ctx do
    mm = %Betty.Metric{measurement: "betty", fields: %{val: true, mod: __MODULE__}, tags: %{test: true}}

    metric_rc = Betty.write_metric(mm)

    fail = "metric rc should be a ok tuple with a map: #{inspect(metric_rc)}"
    assert {:ok, %{}} = metric_rc, fail
  end

  test "can Betty write an %AppError{} to the database", _ctx do
    metric_rc = Betty.app_error(__MODULE__, env: :test, success: false, temp_f: 78.7, val: 42)

    fail = "metric rc should be a ok tuple with a map: #{inspect(metric_rc)}"
    assert {:ok, %{}} = metric_rc, fail
  end
end
