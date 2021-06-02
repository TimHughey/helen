defmodule SallyMsgInTest do
  @moduledoc false

  use ExUnit.Case
  use Should

  alias Sally.MsgIn

  @moduletag :msg_in
  @empty_payload Msgpax.pack!(%{}) |> IO.iodata_to_binary()

  test "can MsgIn handle a well formed payload" do
    map = %{mtime: System.os_time(:millisecond), log: true, roundtrip_ref: "rt_ref", val: 0}

    x = make_msg(map)

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
    mtime = System.os_time(:millisecond) - 5_000
    map = %{mtime: mtime, log: true, roundtrip_ref: "rt_ref"}

    x = make_msg(map)

    fail = pretty("MsgIn did not match", x)
    refute x.valid?, fail
    assert x.invalid_reason == "data is old"
  end

  test "can MsgIn handle a message missing the mtime key" do
    map = %{log: true, roundtrip_ref: "rt_ref"}

    x = make_msg(map)

    fail = pretty("MsgIn did not match", x)
    refute x.valid?, fail
    assert x.invalid_reason == "mtime is missing"
  end

  test "can MsgIn handle a message containing an invalid env" do
    x = MsgIn.create(["breakfix", "ruth.msg_in", "pwm", "msg_in_test", "misc"], @empty_payload)

    fail = pretty("MsgIn did not match", x)
    refute x.valid?, fail
    assert x.invalid_reason == "unknown env filter"
  end

  test "can MsgIn handle a message missing reporting filter" do
    x = MsgIn.create(["test", "ruth.msg_in", "pwm", "msg_in_test", "misc"], @empty_payload)

    fail = pretty("MsgIn did not match", x)
    refute x.valid?, fail
    assert x.invalid_reason == "report filter incorrect"
  end

  test "can MsgIn handle a message missing host filer" do
    x = MsgIn.create(["test", "r"], @empty_payload)

    fail = pretty("MsgIn did not match", x)
    refute x.valid?, fail
    assert x.invalid_reason == "host filter missing"
  end

  test "can MsgIn handle a message missing category filer" do
    x = MsgIn.create(["test", "r", "host"], @empty_payload)

    fail = pretty("MsgIn did not match", x)
    refute x.valid?, fail
    assert x.invalid_reason == "category filter missing"
  end

  test "can MsgIn handle a message missing ident filer" do
    x = MsgIn.create(["test", "r", "host", "category"], @empty_payload)

    fail = pretty("MsgIn did not match", x)
    refute x.valid?, fail
    assert x.invalid_reason == "ident filter missing"
  end

  defp make_msg(map) do
    filters = ["test", "r", "ruth.msg_in", "pwm", "msg_in_test", "misc"]
    payload = Msgpax.pack!(map) |> IO.iodata_to_binary()

    MsgIn.create(filters, payload)
  end
end
