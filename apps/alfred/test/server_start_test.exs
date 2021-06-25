defmodule AlfredServerStartTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag :server_start

  setup_all do
    {:ok, %{}}
  end

  setup ctx do
    ctx
  end

  test "can Alfred start the Names server", _ctx do
    assert Alfred.Names.alive?(), "Names server is not alive"
  end

  test "can Alfred start the Notify server", _ctx do
    assert Alfred.Notify.alive?(), "Notify server is not alive"
  end

  test "can Alfred start the Control server", _ctx do
    assert Alfred.Control.alive?(), "Control server is not alive"
  end
end
