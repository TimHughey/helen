defmodule AlfredTest do
  use ExUnit.Case

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
      assert %Alfred.ExecResult{rc: :ok} = er
    end
  end

  defmacro assert_invalid_exec_result(er, reason) do
    quote bind_quoted: [er: er, reason: reason] do
      assert %Alfred.ExecResult{rc: {:invalid, invalid_reason}} = er
      assert invalid_reason =~ reason
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
      assert Alfred.names_exists?(name)
      assert ^jsr = [name]
    end
  end

  describe "Alfred.names_*" do
    test "available?/2 returns true when a name is not yet registered" do
      assert Alfred.names_available?("foobar")
    end

    @tag name_add: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    @tag just_saw_add: []
    test "available/2 returns true when a name is available", %{name: name} do
      refute Alfred.names_available?(name)
    end

    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "lookup/2 returns an Alfred.KnownName", %{name: name} do
      assert %Alfred.KnownName{name: ^name} = Alfred.names_lookup(name)
    end

    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "exists?/1 returns true when a name is known", %{name: name} do
      assert Alfred.names_exists?(name)
    end

    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "delete/2 removes a known name", %{name: name} do
      assert Alfred.names_delete(name) == name
      refute Alfred.names_exists?(name)
    end
  end

  describe "Alfred.names_known/1" do
    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "returns a list of names by default", %{name: name} do
      assert [] == [name] -- Alfred.names_known()
    end

    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "returns a list of KnownNames", %{name: name} do
      known = Alfred.names_known(details: true)

      assert [%Alfred.KnownName{} | _] = known

      assert Enum.any?(known, fn %KnownName{} = kn -> kn.name == name end)
    end

    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "returns a list of names with seen_at", %{name: name} do
      known = Alfred.names_known(seen_at: true)
      assert [{<<_x::binary>>, %DateTime{}} | _] = known

      assert Enum.any?(known, fn {search, _} -> search == name end)
    end

    @tag name_add: [type: :mut, rc: :ok, cmd: "on"]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "returns a list of tuples of name and seen ago ms", %{name: name} do
      known = Alfred.names_known(seen_ago: true)

      assert [{<<_x::binary>>, seen_ms} | _] = known
      assert is_integer(seen_ms)

      assert Enum.any?(known, fn {search, _} -> search == name end)
    end
  end

  defmacro assert_good_immutable_status(status) do
    quote bind_quoted: [status: status] do
      assert %Alfred.ImmutableStatus{
               name: <<_name::binary>>,
               datapoints: %{temp_f: _},
               good?: true,
               found?: true,
               ttl_expired?: false,
               error: :none,
               status_at: %DateTime{}
             } = status
    end
  end

  defmacro assert_good_mutable_status(status) do
    quote bind_quoted: [status: status] do
      assert %Alfred.MutableStatus{
               name: <<_::binary>>,
               cmd: <<_::binary>>,
               good?: true,
               found?: true,
               ttl_expired?: false,
               error: :none,
               status_at: %DateTime{}
             } = status
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
      assert %Alfred.ImmutableStatus{name: ^name, error: :not_found} = Alfred.status(name)
    end

    @tag name_add: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    @tag just_saw_add: [callback: {:server, FooBar}]
    @tag capture_log: true
    test "handles callback failure for an immutable", %{name: name} do
      assert %Alfred.ImmutableStatus{name: ^name, error: :callback_failed} = Alfred.status(name)
    end

    @tag name_add: [type: :mut, cmd: "on"]
    @tag just_saw_add: [callback: {:server, FooBar}]
    @tag capture_log: true
    test "handles callback failure for a mutable", %{name: name} do
      assert %Alfred.MutableStatus{name: ^name, error: :callback_failed} = Alfred.status(name)
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

      assert {:ok, %Ticket{ref: ticket_ref}} = Alfred.notify_register(opts)

      # run another just saw to trigger a notification

      Alfred.just_saw(ctx.just_saw_add)

      receive do
        {Alfred, %Memo{ref: ^ticket_ref} = memo} -> assert memo
        error -> refute true, "#{inspect(error)} should be {Alfred, %Memo{}}"
      after
        100 -> refute true, "should have received a notification"
      end
    end

    @tag name_add: [type: :imm, rc: :ok, temp_f: 81.1, relhum: 65.1]
    @tag just_saw_add: [callback: {:module, ExecAid}]
    test "unregister/1 reference and unregisters for notifications", ctx do
      alias Alfred.Notify.Ticket
      opts = [name: ctx.name]

      assert {:ok, %Ticket{ref: ticket_ref}} = Alfred.notify_register(opts)
      assert :ok = Alfred.notify_unregister(ticket_ref)
    end
  end
end
