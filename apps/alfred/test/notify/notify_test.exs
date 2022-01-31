defmodule Alfred.NotifyTest do
  use ExUnit.Case, async: true
  use Should

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  @moduletag alfred: true, alfred_notify: true

  setup_all do
    {:ok, %{equipment_add: []}}
  end

  setup [:opts_add, :equipment_add, :notifier_add]

  defmacro assert_registered_name(ctx) do
    quote bind_quoted: [ctx: ctx] do
      assert %{registered_name: registered_name} = ctx
      assert {:ok, %Alfred.Ticket{name: name, ref: ref, notifier_pid: pid}} = registered_name
      assert Process.alive?(pid)

      {name, pid, ref}
    end
  end

  describe "Alfred.Notify.find_registration/1" do
    @tag notifier_add: []
    test "returns registration for the reference", ctx do
      {name, notifier_pid, ref} = assert_registered_name(ctx)
      caller_pid = self()

      assert {^name, ^notifier_pid, {^caller_pid, ^ref}} = Alfred.Notify.find_registration(ref)
    end
  end

  describe "Alfred.Notify.register/2" do
    @tag equipment_add: []
    test "starts Notify for name, properly links and shuts down", %{equipment: name} do
      test_pid = self()

      # NOTE: we spawn a new process to be the notification requester allowing validation
      # of the correct linakges. the spawned process sends the test process a message
      # containing the its pid and the results of Alfred.Notify.register/2.
      # The notification requestor then sleeps while validations are completed. Finally,
      # the process is killed to validate proper shutdown of the notifier process.

      spawn(fn ->
        Alfred.Notify.register(name, [])
        |> then(fn rc -> Process.send(test_pid, {self(), rc}, []) end)
        |> tap(fn _ -> Process.sleep(10_000) end)
      end)

      receive do
        {link_pid, {:ok, %Alfred.Ticket{notifier_pid: notifier_pid}}} ->
          # validate the notifier pid is properly supervised
          assert Enum.any?(Supervisor.which_children(Alfred.Notify.DynamicSupervisor), fn
                   {:undefined, ^notifier_pid, :worker, [Alfred.Notify]} -> true
                   _ -> false
                 end)

          # validate the notify process is linked to it's requestor
          assert [links: [^notifier_pid]] = Keyword.take(Process.info(link_pid), [:links])

          # kill the notifier requestor, validate the notifier terminates and the
          # registry removes the registration
          assert Process.exit(link_pid, :stop)

          # allow time for spawned pid and linked notifier to terminate
          Process.sleep(10)

          refute Process.alive?(link_pid)
          refute Process.alive?(notifier_pid)
          assert [] = Registry.lookup(Alfred.Notify.Registry, link_pid)

        any ->
          refute any, "wrong message received: #{inspect(any, pretty: true)}"
      after
        # allow a timeout since it appears compile time may impact the test
        150 -> refute true, "timeout"
      end
    end

    @tag notifier_add: []
    test "handles previously registered name (does not start a duplicate notifier)", ctx do
      {name, _pid, ref} = assert_registered_name(ctx)

      assert {:ok, %Alfred.Ticket{name: ^name, ref: ^ref, opts: %{}}} = Alfred.Notify.register(name, [])
    end
  end

  describe "Alfred.Notify.unregister/1" do
    @tag notifier_add: []
    test "stops notifier", ctx do
      {_name, notifier_pid, ref} = reg_tuple = assert_registered_name(ctx)

      assert :ok = Alfred.Notify.unregister(ref)
      refute Process.alive?(notifier_pid)

      assert :success == wait_for_removal(reg_tuple)
    end

    test "handles unknown reference" do
      ref = make_ref()

      assert :ok = Alfred.Notify.unregister(ref)
    end
  end

  describe "Alfred.Notify honors missing ms" do
    @tag notifier_add: [missing_ms: 0, send_missing_msg: true]
    test "when ms == 100", ctx do
      {name, _pid, ref} = assert_registered_name(ctx)

      pid = self()

      # NOTE: the minimum allowed missing ms is 100
      assert_receive({Alfred, memo}, 200)
      assert %Alfred.Memo{name: ^name, pid: ^pid, ref: ^ref, missing?: true} = memo
    end
  end

  @bad_msg {:bad_msg}
  describe "Alfred.Notify error handling:" do
    @tag notifier_add: []
    test "all bad msgs", ctx do
      {_name, pid, _ref} = assert_registered_name(ctx)

      assert capture_log(fn -> assert :error = Alfred.Notify.call(@bad_msg, pid) end) =~ ~r/bad_msg/
      assert :ok = GenServer.cast(pid, @bad_msg)
      assert :ok = Process.send(pid, @bad_msg, [])

      # allow processing of cast and info messages
      Process.sleep(10)
    end

    test "call/2" do
      pid = spawn(fn -> nil end)

      assert {:no_server, _pid} = Alfred.Notify.call(@bad_msg, pid)
      assert capture_io(fn -> Alfred.Notify.call(@bad_msg, self()) end) =~ ~r/call itself/
    end

    @tag notifier_add: []
    test "handle_call({:get, key}, from, state)", ctx do
      {_name, pid, _ref} = assert_registered_name(ctx)
      assert {:bad_path, :unknown} = GenServer.call(pid, {:get, :unknown})
    end
  end

  def opts_add(ctx) do
    opts_default = [interval_ms: :all]

    case ctx do
      %{opts_add: opts} -> %{opts: Keyword.merge(opts_default, opts)}
      _ -> %{opts: opts_default}
    end
  end

  def wait_for_removal({name, notifier_pid, ref}) do
    caller_pid = self()

    Enum.reduce(1..10, :ok, fn
      _, :sleep -> Process.sleep(3)
      _, :ok -> Alfred.Notify.find_registration(ref)
      _, {^name, ^notifier_pid, {^caller_pid, ^ref}} -> :sleep
      _, [] -> :success
      _, done -> done
    end)
  end

  def equipment_add(ctx), do: Alfred.NamesAid.equipment_add(ctx)

  def notifier_add(%{notifier_add: opts, equipment: name}) do
    %{registered_name: Alfred.Notify.register(name, opts)}
  end

  def notifier_add(_ctx), do: :ok
end
