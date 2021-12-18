defmodule AlfredTest do
  use ExUnit.Case
  use Should

  @moduletag alfred: true, alfred_api: true

  alias Alfred.ExecAid
  import Alfred.ExecAid, only: [exec_cmd_from_parts_add: 1]

  import Alfred.NamesAid,
    only: [just_saw_add: 1, name_add: 1, parts_add_auto: 1, parts_add: 1, seen_name_add: 1]

  alias Alfred.KnownName

  alias Alfred.StatusAid

  setup [:name_add, :parts_add_auto, :parts_add, :seen_name_add, :just_saw_add, :exec_cmd_from_parts_add]

  defmacro assert_valid_exec_result(er) do
    quote bind_quoted: [er: er] do
      Should.Be.Struct.with_all_key_value(er, Alfred.ExecResult, rc: :ok)
    end
  end

  defmacro assert_invalid_exec_result(er, reason) do
    quote bind_quoted: [er: er, reason: reason] do
      er
      |> Should.Be.Struct.with_key(Alfred.ExecResult, :rc)
      # validate :rc key is a tuple and contains reqson
      |> Should.Be.Tuple.rc_and_binaries(:invalid, [reason])
    end
  end

  describe "Alfred.execute/2" do
    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    @tag exec_cmd_from_parts_add: []
    test "processes a well formed ExecCmd", %{name: _, exec_cmd_from_parts: ec} do
      Alfred.execute(ec, [])
      |> assert_valid_exec_result()
    end

    @tag name_add: [type: :mut, rc: :ok, cmd: "special"]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    @tag exec_cmd_from_parts_add: []
    test "requires type for cmds other than on/off", %{name: _, exec_cmd_from_parts: ec} do
      Alfred.execute(ec)
      |> assert_invalid_exec_result("must include type")
    end

    @tag name_add: [type: :imm, rc: :ok, temp_f: 86.1]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "requires known name is a mutable", %{name: name} do
      [name: name, cmd: "on"]
      |> Alfred.ExecCmd.new()
      |> Alfred.execute()
      |> assert_invalid_exec_result("mutable")
    end

    test "requires an known name" do
      [name: "foo bar", cmd: "on"]
      |> Alfred.ExecCmd.new()
      |> Alfred.execute()
      |> assert_invalid_exec_result("unknown")
    end

    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:server, FooBar}]
    @tag exec_cmd_from_parts_add: []
    @tag capture_log: true
    test "handles callback failure", %{name: _, exec_cmd_from_parts: ec} do
      ec
      |> Alfred.execute()
      |> assert_invalid_exec_result("callback failed")
    end

    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: &ExecAid.execute/2]
    @tag exec_cmd_from_parts_add: []
    test "honors a function as the callback", %{exec_cmd_from_parts: ec} do
      ec
      |> Alfred.execute([])
      |> assert_valid_exec_result()
    end

    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "accepts a binary name and list of opts", %{name: name} do
      params = [type: "fixed", percent: 50]
      cmd_opts = [notify_when_released: true]
      opts = [cmd: "low speed", params: params, cmd_opts: cmd_opts, pub_opts: []]

      Alfred.execute(name, opts)
      |> assert_valid_exec_result()
    end

    @tag name_add: [type: :mut, cmd: "on", expired_ms: 1000]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    @tag exec_cmd_from_parts_add: []
    test "detects missing name", %{exec_cmd_from_parts: ec} do
      Alfred.execute(ec)
      |> assert_invalid_exec_result("missing")
    end
  end

  describe "Alfred.just_saw/2" do
    @tag name_add: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    @tag just_saw_add: []
    test "processes a well formed %JustSaw{}", %{just_saw_result: jsr, name: name} do
      Should.Be.asserted(fn -> Alfred.names_exists?(name) end)
      Should.Be.match(jsr, [name])
    end
  end

  describe "Alfred.names_*" do
    test "available?/2 returns false when a name is not available" do
      Should.Be.asserted(fn -> Alfred.names_available?("foobar") end)
    end

    @tag name_add: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    @tag just_saw_add: []
    test "available/2 returns true when a name is available", %{name: name} do
      Should.Be.refuted(fn -> Alfred.names_available?(name) end)
    end

    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "lookup/2 returns an Alfred.KnownName", %{name: name} do
      name
      |> Alfred.names_lookup()
      |> Should.Be.struct(KnownName)
    end

    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "exists?/1 returns true when a name is known", %{name: name} do
      Should.Be.asserted(fn -> Alfred.names_exists?(name) end)
    end

    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "delete/2 removes a known name", %{name: name} do
      Should.Be.asserted(fn -> Alfred.names_delete(name) == name end)
      Should.Be.refuted(fn -> Alfred.names_exists?(name) end)
    end
  end

  describe "Alfred.names_known/1" do
    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "returns a list of names by default", %{name: name} do
      Alfred.names_known()
      |> Should.Be.List.of_binaries()
      |> Should.Contain.value(name)
    end

    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "returns a list of KnownNames", %{name: name} do
      known = Alfred.names_known(details: true) |> Should.Be.List.of_structs(KnownName)

      found? = Enum.any?(known, fn %KnownName{} = kn -> kn.name == name end)
      assert found?, msg(known, "should contain a KnownName for", name)
    end

    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "returns a list of names with seen_at", %{name: name} do
      Alfred.names_known(seen_at: true)
      |> Should.Be.List.of_tuples_with_size(2)
      |> tap(fn [x | _] -> Should.Be.Tuple.of_types(x, 2, [:binary, :datetime]) end)
      |> Should.Contain.value(name)
    end

    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "returns a list of tuples of name and seen ago ms", %{name: name} do
      Alfred.names_known(seen_ago: true)
      |> Should.Be.List.of_tuples_with_size(2)
      |> tap(fn [x | _] -> Should.Be.Tuple.of_types(x, 2, [:binary, :integer]) end)
      |> Should.Contain.value(name)
    end
  end

  defmacro assert_good_immutable_status(status) do
    quote bind_quoted: [status: status] do
      want_struct = Alfred.ImmutableStatus
      want_types = [name: :binary, datapoints: :map, status_at: :datetime]
      want_kv = [good?: true, found?: true, ttl_expired?: false, error: :none]

      status
      |> Should.Be.Struct.of_key_types(want_struct, want_types)
      |> Should.Be.Struct.with_all_key_value(want_struct, want_kv)

      Should.Be.Map.with_keys(status.datapoints, [:temp_f])
    end
  end

  defmacro assert_good_mutable_status(status) do
    quote bind_quoted: [status: status] do
      want_struct = Alfred.MutableStatus
      want_types = [name: :binary, cmd: :binary, status_at: :datetime]
      want_kv = [good?: true, found?: true, ttl_expired?: false, error: :none]

      status
      |> Should.Be.Struct.of_key_types(want_struct, want_types)
      |> Should.Be.Struct.with_all_key_value(want_struct, want_kv)
    end
  end

  describe "Alfred.status/2" do
    @tag name_add: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    @tag just_saw_add: [callback: {:module, StatusAid}]
    test "returns a well formed Alfred.ImmutableStatus", %{name: name} do
      status = Alfred.status(name, [])
      assert_good_immutable_status(status)
    end

    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:module, StatusAid}]
    test "returns a well formed Alfred.MutableStatus", %{name: name} do
      status = Alfred.status(name, [])
      assert_good_mutable_status(status)
    end

    @tag name_add: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    test "returns an ImmutableStatus with error when name unknown", %{name: name} do
      want_struct = Alfred.ImmutableStatus

      name
      |> Alfred.status()
      |> Should.Be.Struct.with_all_key_value(want_struct, error: :not_found)
    end

    @tag name_add: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    @tag just_saw_add: [callback: {:server, FooBar}]
    @tag capture_log: true
    test "handles callback failure for an immutable", %{name: name} do
      want_struct = Alfred.ImmutableStatus

      name
      |> Alfred.status()
      |> Should.Be.Struct.with_all_key_value(want_struct, error: :callback_failed)
    end

    @tag name_add: [type: :mut, cmd: "on"]
    @tag just_saw_add: [callback: {:server, FooBar}]
    @tag capture_log: true
    test "handles callback failure for a mutable", %{name: name} do
      want_struct = Alfred.MutableStatus

      name
      |> Alfred.status()
      |> Should.Be.Struct.with_all_key_value(want_struct, error: :callback_failed)
    end

    @tag name_add: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    @tag just_saw_add: [callback: &StatusAid.status/3]
    test "honors a function as a callback for an immutable", %{name: name} do
      name
      |> Alfred.status([])
      |> assert_good_immutable_status()
    end
  end

  describe "Alfred.notify_*" do
    @tag name_add: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "register/1 accepts a list of opts and registers for notifications", ctx do
      alias Alfred.Notify.{Memo, Ticket}
      opts = [name: ctx.name]

      ticket =
        Alfred.notify_register(opts)
        |> Should.Be.Ok.tuple_with_struct(Ticket)

      # run another just saw to trigger a notification

      Alfred.just_saw(ctx.just_saw_add)

      receive do
        {Alfred, %Memo{} = memo} -> Should.Be.equal(memo.ref, ticket.ref)
        error -> refute true, Should.msg(error, "should be {Alfred, %Memo{}}")
      after
        100 -> refute true, "should have received a notification"
      end
    end

    @tag name_add: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "unregister/1 reference and unregisters for notifications", ctx do
      alias Alfred.Notify.Ticket
      opts = [name: ctx.name]

      Alfred.notify_register(opts)
      |> Should.Be.Ok.tuple_with_struct(Ticket)
      |> then(fn ticket -> Alfred.notify_unregister(ticket.ref) end)
      |> Should.Be.ok()
    end
  end
end
