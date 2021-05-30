defmodule SallyMsgInTest do
  @moduledoc false

  use ExUnit.Case
  use Should

  alias Sally.MsgIn

  @moduletag :msg_in

  test "can MsgIn handle a well formed payload" do
    map = %{mtime: System.os_time(:second), log: true, roundtrip_ref: "rt_ref", val: 0}

    x = make_msg(map) |> MsgIn.preprocess()

    fail = pretty("MsgIn did not match", x)
    assert x.valid? == true, fail
    assert is_map(x.data), fail
    refute x.data[:mtime] == map.mtime, fail
    refute x.data[:roundtrip_ref] == map.roundtrip_ref, fail
    assert x.data[:val] == 0, fail
    assert x.log == [msg: true], fail
    assert x.roundtrip_ref == map.roundtrip_ref
  end

  test "can MsgIn handle an old message" do
    map = %{mtime: System.os_time(:second) - 10, log: true, roundtrip_ref: "rt_ref"}

    x = make_msg(map) |> MsgIn.preprocess()

    fail = pretty("MsgIn did not match", x)
    refute x.valid?, fail
    assert x.invalid_reason == "data is old"
  end

  test "can MsgIn handle a message missing the mtime key" do
    map = %{log: true, roundtrip_ref: "rt_ref"}

    x = make_msg(map) |> MsgIn.preprocess()

    fail = pretty("MsgIn did not match", x)
    refute x.valid?, fail
    assert x.invalid_reason == "mtime key missing"
  end

  defp make_msg(map) do
    %MsgIn{
      payload: Msgpax.pack!(map) |> IO.iodata_to_binary(),
      env: "test",
      host: "ruth.msg_in",
      type: "msg_in_test",
      at: DateTime.utc_now()
    }
  end
end
