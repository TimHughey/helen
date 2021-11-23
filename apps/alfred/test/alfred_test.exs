defmodule AlfredTest do
  use ExUnit.Case
  use Should

  @moduletag alfred: true, alfred_api: true

  use Alfred.ExecAid
  use Alfred.NamesAid
  use Alfred.StatusAid

  setup [:make_name, :make_parts_auto, :make_parts, :make_seen_name, :just_saw, :make_exec_cmd]

  defmacro should_be_valid_exec_result(er) do
    quote bind_quoted: [er: er] do
      should_be_struct(er, Alfred.ExecResult)
      should_be_equal(er.rc, :ok)
    end
  end

  defmacro should_be_invalid_exec_result(er, reason) do
    quote bind_quoted: [er: er, reason: reason] do
      should_be_struct(er, Alfred.ExecResult)
      reason = should_be_invalid_tuple(er.rc)
      should_contain_binaries(reason, [reason])
    end
  end

  describe "Alfred.execute/2" do
    @tag make_name: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw: [callback: {:module, ExecAid}]
    @tag make_exec_cmd: []
    test "processes a well formed ExecCmd", %{name: _, exec_cmd: ec} do
      er = Alfred.execute(ec, [])
      should_be_valid_exec_result(er)
    end

    @tag make_name: [type: :mut, rc: :ok, cmd: "special"]
    @tag just_saw: [callback: {:module, ExecAid}]
    @tag make_exec_cmd: []
    test "requires type for cmds other than on/off", %{name: _, exec_cmd: ec} do
      er = Alfred.execute(ec)
      should_be_struct(er, Alfred.ExecResult)
      invalid_reason = should_be_invalid_tuple(er.rc)
      should_contain_binaries(invalid_reason, ["must include type"])
    end

    @tag make_name: [type: :imm, rc: :ok, temp_f: 86.1]
    @tag just_saw: [callback: {:module, ExecAid}]
    test "requires known name is a mutable", %{name: name} do
      ec = %Alfred.ExecCmd{name: name, cmd: "on"}
      er = Alfred.execute(ec)
      should_be_struct(er, Alfred.ExecResult)
      reason = should_be_invalid_tuple(er.rc)
      should_contain_binaries(reason, ["mutable"])
    end

    test "requires an known name" do
      ec = %Alfred.ExecCmd{name: "foo bar", cmd: "on"}
      er = Alfred.execute(ec)
      should_be_invalid_exec_result(er, "unknown")
    end

    @tag make_name: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw: [callback: {:server, FooBar}]
    @tag make_exec_cmd: []
    @tag capture_log: true
    test "handles callback failure", %{name: _, exec_cmd: ec} do
      er = Alfred.execute(ec)
      should_be_struct(er, Alfred.ExecResult)
      reason = should_be_invalid_tuple(er.rc)
      should_contain_binaries(reason, ["callback failed"])
    end

    @tag make_name: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw: [callback: &ExecAid.execute/2]
    @tag make_exec_cmd: []
    test "honors a function as the callback", %{exec_cmd: ec} do
      er = Alfred.execute(ec, [])
      should_be_valid_exec_result(er)
    end

    @tag make_name: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw: [callback: {:module, ExecAid}]
    test "accepts a binary name and list of opts", %{name: name} do
      params = [type: "fixed", percent: 50]
      cmd_opts = [notify_when_released: true]
      opts = [cmd: "low speed", params: params, cmd_opts: cmd_opts, pub_opts: []]

      er = Alfred.execute(name, opts)
      should_be_valid_exec_result(er)
    end

    @tag make_name: [type: :mut, cmd: "on", expired_ms: 1000]
    @tag just_saw: [callback: {:module, ExecAid}]
    @tag make_exec_cmd: []
    test "detects missing name", %{exec_cmd: ec} do
      er = Alfred.execute(ec)
      should_be_invalid_exec_result(er, "missing")
    end
  end

  describe "Alfred.just_saw/2" do
    @tag make_name: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    @tag just_saw: []
    test "processes a well formed %JustSaw{}", %{just_saw_result: jsr, name: name} do
      should_be_equal(Alfred.names_exists?(name), true)
      should_be_equal(jsr, [name])
    end
  end

  describe "Alfred.names_*" do
    test "available?/2 returns false when a name is not available" do
      res = Alfred.names_available?("foobar")
      should_be_equal(res, true)
    end

    @tag make_name: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    # @tag just_saw: []
    test "available/2 returns true when a name is available", %{name: name} do
      res = Alfred.names_available?(name)
      should_be_true(res)
    end

    @tag make_name: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw: [callback: {:module, ExecAid}]
    test "lookup/2 returns an Alfred.KnownName", %{name: name} do
      known_name = Alfred.names_lookup(name)
      should_be_struct(known_name, Alfred.KnownName)
    end

    @tag make_name: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw: [callback: {:module, ExecAid}]
    test "exists?/1 returns true when a name is known", %{name: name} do
      rc = Alfred.names_exists?(name)

      should_be_true(rc)
    end

    @tag make_name: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw: [callback: {:module, ExecAid}]
    test "delete/2 removes a known name", %{name: name} do
      deleted_name = Alfred.names_delete(name)
      should_be_equal(name, deleted_name)

      rc = Alfred.names_exists?(name)
      should_be_false(rc)
    end
  end

  describe "Alfred.names_known/1" do
    @tag make_name: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw: [callback: {:module, ExecAid}]
    test "returns a list of names by default", %{name: name} do
      known = Alfred.names_known()
      should_be_non_empty_list(known)
      should_contain_value(known, name)
    end

    @tag make_name: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw: [callback: {:module, ExecAid}]
    test "returns a list of KnownNames", %{name: name} do
      alias Alfred.KnownName

      known = Alfred.names_known(details: true)
      should_be_non_empty_list(known)
      first = List.first(known)
      should_be_struct(first, KnownName)

      found? = Enum.any?(known, fn %KnownName{} = kn -> kn.name == name end)
      assert found?, msg(known, "should contain a KnownName for", name)
    end

    @tag make_name: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw: [callback: {:module, ExecAid}]
    test "returns a list of names with seen_at", %{name: name} do
      known = Alfred.names_known(seen_at: true)
      should_be_non_empty_list(known)

      first = List.first(known)
      {check_name, check_dt} = should_be_tuple_with_size(first, 2)
      should_be_binary(check_name)
      should_be_datetime(check_dt)

      found? = Enum.any?(known, fn {x, _dt} -> x == name end)
      assert found?, msg(known, "should contain a tuple for", name)
    end

    @tag make_name: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw: [callback: {:module, ExecAid}]
    test "returns a list of tuples of name and seen ago ms", %{name: name} do
      known = Alfred.names_known(seen_ago: true)
      should_be_non_empty_list(known)

      first = List.first(known)
      {check_name, check_ms} = should_be_tuple_with_size(first, 2)
      should_be_binary(check_name)
      assert is_integer(check_ms), msg(check_ms, "should be an integer")

      found? = Enum.any?(known, fn {x, _dt} -> x == name end)
      assert found?, msg(known, "should contain a tuple for", name)
    end
  end

  defmacro should_be_good_immutable_status(status) do
    quote bind_quoted: [status: status] do
      should_be_struct(status, Alfred.ImmutableStatus)
      should_be_binary(status.name)
      should_be_true(status.good?)
      should_be_true(status.found?)
      should_be_map_with_keys(status.datapoints, [:temp_f])
      should_be_datetime(status.status_at)
      should_be_false(status.ttl_expired?)
      should_be_equal(status.error, :none)
    end
  end

  defmacro should_be_good_mutable_status(status) do
    quote bind_quoted: [status: status] do
      should_be_struct(status, Alfred.MutableStatus)
      should_be_binary(status.name)
      should_be_true(status.good?)
      should_be_true(status.found?)
      should_be_binary(status.cmd)
      should_be_datetime(status.status_at)
      should_be_false(status.ttl_expired?)
      should_be_equal(status.error, :none)
    end
  end

  describe "Alfred.status/2" do
    @tag make_name: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    @tag just_saw: [callback: {:module, StatusAid}]
    test "returns a well formed Alfred.ImmutableStatus", %{name: name} do
      status = Alfred.status(name, [])
      should_be_good_immutable_status(status)
    end

    @tag make_name: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw: [callback: {:module, StatusAid}]
    test "returns a well formed Alfred.MutableStatus", %{name: name} do
      status = Alfred.status(name, [])
      should_be_good_mutable_status(status)
    end

    @tag make_name: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    test "returns an ImmutableStatus with error when name unknown", %{name: name} do
      status = Alfred.status(name)

      should_be_struct(status, Alfred.ImmutableStatus)
      should_be_equal(status.error, :unknown)
    end

    @tag make_name: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    @tag just_saw: [callback: {:server, FooBar}]
    @tag capture_log: true
    test "handles callback failure for an immutable", %{name: name} do
      status = Alfred.status(name, [])
      should_be_struct(status, Alfred.ImmutableStatus)
      should_be_equal(status.error, :callback_failed)
    end

    @tag make_name: [type: :mut, cmd: "on"]
    @tag just_saw: [callback: {:server, FooBar}]
    @tag capture_log: true
    test "handles callback failure for a mutable", %{name: name} do
      status = Alfred.status(name, [])
      should_be_struct(status, Alfred.MutableStatus)
      should_be_equal(status.error, :callback_failed)
    end

    @tag make_name: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    @tag just_saw: [callback: &StatusAid.status/3]
    test "honors a function as a callback for an immutable", %{name: name} do
      status = Alfred.status(name, [])
      should_be_good_immutable_status(status)
    end
  end

  describe "Alfred.notify_*" do
    @tag make_name: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    @tag just_saw: [callback: {:module, ExecAid}]
    test "register/1 accepts a list of opts and registers for notifications", ctx do
      alias Alfred.Notify.{Memo, Ticket}
      opts = [name: ctx.name]

      res = Alfred.notify_register(opts)
      ticket = should_be_ok_tuple_with_struct(res, Ticket)

      # run another just saw to trigger a notification

      Alfred.just_saw(ctx.just_saw)

      receive do
        msg ->
          memo = should_be_msg_tuple_with_mod_and_struct(msg, Alfred, Memo)
          should_be_equal(memo.ref, ticket.ref)
      after
        100 -> refute true, "should have received a notification"
      end
    end

    @tag make_name: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    @tag just_saw: [callback: {:module, ExecAid}]
    test "unregister/1 reference and unregisters for notifications", ctx do
      alias Alfred.Notify.Ticket
      opts = [name: ctx.name]

      res = Alfred.notify_register(opts)
      ticket = should_be_ok_tuple_with_struct(res, Ticket)

      res = Alfred.notify_unregister(ticket.ref)

      should_be_simple_ok(res)
    end
  end
end
