defmodule HelenServerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  @moduletag :helen_server

  test "helen supervisor started and is global" do
    pid = GenServer.whereis({:global, :helen_supervisor})

    assert is_pid(pid)
  end

  test "helen server started and is global" do
    pid = GenServer.whereis({:global, :helen_server})

    assert is_pid(pid)
  end

  test "helen server handles a quoted block" do
    block =
      quote do
        Sensor.temperature(name: "unknown sensor", since_secs: 30)
      end

    res = GenServer.call({:global, :helen_server}, block)

    assert is_nil(res)
  end

  test "helen server gracefully poorly formed handle_call messages" do
    res = GenServer.call({:global, :helen_server}, :foobar)

    assert is_tuple(res)
    assert {:unhandled, _msg} = res
  end
end
