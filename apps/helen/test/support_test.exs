defmodule HelenTestSupportTest do
  use ExUnit.Case

  import HelenTestHelpers, only: [pretty: 1]

  @moduletag :helen_test_support

  test "can test support create an inbound switch msg" do
    opts = [type: "switch"]
    msg = MsgTestHelper.switch_msg(opts)

    for key <- [:payload, :host, :msg_recv_dt, :topic] do
      fail = "message should have key #{inspect(key)}#{pretty(msg)}"
      assert is_map_key(msg, key), fail
    end
  end
end
