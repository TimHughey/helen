defmodule AlfredServerStartTest do
  use ExUnit.Case
  use AlfredTestShould

  alias Alfred.{ControlServer, NamesAgent, NotifyServer}

  @moduletag :server_start

  setup_all do
    {:ok, %{}}
  end

  setup ctx do
    ctx
  end

  test "can Alfred start the Names Agent", _ctx do
    pid = NamesAgent.pid()
    should_be_pid(pid)
  end

  test "can Alfred start the Notify server", _ctx do
    pid = GenServer.whereis(NotifyServer)
    should_be_pid(pid)
  end

  test "can Alfred start the Control server", _ctx do
    pid = GenServer.whereis(ControlServer)
    should_be_pid(pid)
  end
end
