defmodule AlfredNamesAidTest do
  use ExUnit.Case, async: true
  use Should

  @moduletag alfred: true, alfred_names_aid: true

  import Alfred.NamesAid, only: [name_add: 1, parts_add: 1, parts_add_auto: 1]

  setup [:name_add, :parts_add_auto, :parts_add]

  describe "binary_from_opts/2 and binary_to_parts/1" do
    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    test "makes mutable name with rc ok and cmd on", %{name: name, parts: parts} do
      Should.Contain.binaries(name, ["mutable", "ok", "on"])

      want_kv = [name: name, rc: :ok, cmd: "on", type: :mut]
      Should.Be.Map.with_all_key_value(parts, want_kv)
    end

    @tag name_add: [type: :mut, rc: :pending, cmd: "on"]
    test "makes mutable name with rc pending and cmd on", %{name: name, parts: parts} do
      Should.Contain.binaries(name, ["mutable", "pending", "on"])

      want_kv = [name: name, rc: :pending, cmd: "on", type: :mut]
      Should.Be.Map.with_all_key_value(parts, want_kv)
    end

    @tag name_add: [type: :mut, cmd: "on", expired_ms: 1000]
    test "makes mutable name expired with cmd on", %{name: name, parts: parts} do
      Should.Contain.binaries(name, ["mutable", "expired", "on", "expired_ms=1000"])

      want_kv = [name: name, rc: :expired, cmd: "on", type: :mut, expired_ms: 1000]
      Should.Be.Map.with_all_key_value(parts, want_kv)
    end

    @tag name_add: [type: :imm, rc: :ok, temp_f: 86.1, relhum: 65.1]
    test "makes immutable name with rc ok, temp_f and relhum", %{name: name, parts: parts} do
      Should.Contain.binaries(name, ["immutable", "ok", "temp_f", "relhum"])

      want_kv = [name: name, rc: :ok, type: :imm, temp_f: 86.1, relhum: 65.1]
      Should.Be.Map.with_all_key_value(parts, want_kv)
    end

    @tag name_add: [type: :unk]
    test "makes unknown name with rc unknown", %{name: name, parts: parts} do
      Should.Contain.binaries(name, ["unknown"])

      want_kv = [name: name, rc: :unknown, type: :unk]
      Should.Be.Map.with_all_key_value(parts, want_kv)
    end
  end
end
