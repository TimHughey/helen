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

  test "helen server handles sensor messages" do
    res =
      GenServer.call({:global, :helen_server}, %{
        module: :sensor,
        function: :temperature,
        args: [[name: "unknown sensor", since_secs: 30]]
      })

    assert is_nil(res)
  end

  test "helen server handles switch messages" do
    res =
      GenServer.call({:global, :helen_server}, %{
        module: :switch,
        function: :position,
        args: ["unknown switch"]
      })

    assert {:not_found, "unknown switch"} == res
  end

  test "helen server gracefully handles exceptions from apply/3" do
    res =
      GenServer.call({:global, :helen_server}, %{
        module: :sensor,
        function: :temperature,
        args: [name: "unknown sensor", since_secs: 30]
      })

    assert res == %UndefinedFunctionError{
             arity: 2,
             function: :temperature,
             module: Sensor
           }

    assert is_struct(res)
  end
end
