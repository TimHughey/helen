defmodule LightDeskTest do
  @moduledoc false

  use ExUnit.Case, async: false

  setup_all do
    %{}
  end

  setup context do
    context
  end

  test "LightDesk can TX a mode dance payload" do
    rc = LightDesk.mode(:dance)

    assert [lightdesk: {"roost-beta", :ok, _}] = rc
  end

  test "LightDesk can change lightdesk host and TX a mode dance payload" do
    LightDesk.remote_host("test-with-devs")

    rc = LightDesk.mode(:dance)

    assert [lightdesk: {"test-with-devs", :ok, _}] = rc
  end
end
