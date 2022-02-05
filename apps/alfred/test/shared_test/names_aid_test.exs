defmodule AlfredNamesAidTest do
  use ExUnit.Case, async: true
  use Alfred.TestAid

  @moduletag alfred: true, alfred_names_aid: true

  setup [:name_add, :parts_auto_add, :parts_add]

  defmacro assert_binaries(name, binaries) do
    quote bind_quoted: [name: name, binaries: binaries] do
      Enum.all?(binaries, fn want_binary -> assert name =~ want_binary end)
    end
  end

  describe "binary_from_opts/2 and binary_to_parts/1" do
    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    test "makes mutable name with rc ok and cmd on", %{name: name, parts: parts} do
      assert_binaries(name, ["mutable", "ok", "on"])

      assert %{name: ^name, rc: :ok, cmd: "on", type: :mut} = parts
    end

    @tag name_add: [type: :mut, rc: :busy, cmd: "on"]
    test "makes mutable name with rc busy and cmd on", %{name: name, parts: parts} do
      assert_binaries(name, ["mutable", "busy", "on"])

      assert %{name: ^name, rc: :busy, cmd: "on", type: :mut} = parts
    end

    @tag name_add: [type: :mut, rc: :timeout, cmd: "on"]
    test "makes mutable name with rc timeout and cmd on", %{name: name, parts: parts} do
      assert_binaries(name, ["mutable", "timeout", "on"])

      assert %{name: ^name, rc: :timeout, cmd: "on", type: :mut} = parts
    end

    @tag name_add: [type: :mut, cmd: "on", expired_ms: 1000]
    test "makes mutable name expired with cmd on", %{name: name, parts: parts} do
      assert_binaries(name, ["mutable", "expired", "on", "expired_ms=1000"])

      assert %{name: ^name, rc: :expired, cmd: "on", type: :mut, expired_ms: 1000} = parts
    end

    @tag name_add: [type: :imm, rc: :ok, temp_f: 86.1, relhum: 65.1]
    test "makes immutable name with rc ok, temp_f and relhum", %{name: name, parts: parts} do
      assert_binaries(name, ["immutable", "ok", "temp_f", "relhum"])

      assert %{name: ^name, rc: :ok, type: :imm, temp_f: 86.1, relhum: 65.1} = parts
    end

    @tag name_add: [type: :unk]
    test "makes unknown name with rc unknown", %{name: name, parts: parts} do
      assert_binaries(name, ["unknown"])

      assert %{name: ^name, rc: :unknown, type: :unk} = parts
    end
  end
end
