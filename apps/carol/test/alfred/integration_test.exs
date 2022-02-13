defmodule Carol.ExecuteCmd.Test do
  use ExUnit.Case, async: true
  use Carol.TestAid

  @moduletag carol: true, carol_alfred_integration: true

  setup [:init_add]

  describe "Carol.Server.execute_cmd/2" do
    @tag init_add: [episodes: {:short, [future: 12, now: 1, past: 1]}]
    test "handles restart cmd", ctx do
      assert %{init_args: init_args, dev_alias: dev_alias, instance: instance} = ctx
      assert %{name: <<_::binary>>} = dev_alias
      assert <<_::binary>> = instance

      server = get_in(init_args, [:instance])
      assert <<_::binary>> = server

      assert {:ok, pid} = GenServer.start_link(Carol.Server, init_args, [])
      assert is_pid(pid) and Process.alive?(pid)
      # NOTE: receive the first noreply for bootstrap
      assert_receive({:noreply, %Carol.State{}}, 200)

      # NOTE: call register/1 on the equipment to trigger a notify
      Alfred.DevAlias.register(dev_alias)
      # NOTE: receive the second noreply for the first tick
      assert_receive({:noreply, %Carol.State{}}, 200)

      cmd = "restart"
      execute = Alfred.execute(name: server, cmd: cmd)
      assert %Alfred.Execute{rc: :ok, story: %{cmd: ^cmd}} = execute

      Process.sleep(100)
      refute Process.alive?(pid)
    end

    @tag init_add: [episodes: {:short, [future: 12, now: 1, past: 1]}]
    test "handles pause cmd", ctx do
      assert %{init_args: init_args, dev_alias: dev_alias, instance: instance} = ctx
      assert %{name: <<_::binary>>} = dev_alias
      assert <<_::binary>> = instance

      server = get_in(init_args, [:instance])
      assert <<_::binary>> = server

      assert {:ok, pid} = GenServer.start_link(Carol.Server, init_args, [])
      assert is_pid(pid) and Process.alive?(pid)
      # NOTE: receive the first noreply for bootstrap
      assert_receive({:noreply, %Carol.State{}}, 200)

      # NOTE: call register/1 on the equipment to trigger a notify
      Alfred.DevAlias.register(dev_alias)
      # NOTE: receive the second noreply for the first tick
      assert_receive({:noreply, %Carol.State{}}, 200)

      # TODO: enhance assertions to check for pause and resumt
      cmd = "pause"
      execute = Alfred.execute(name: server, cmd: cmd)

      assert %Alfred.Execute{rc: :ok, story: %{cmd: ^cmd}} = execute

      status = Alfred.status(server)
      assert %Alfred.Status{story: story} = status
      assert %{notify: "disabled"} = story
    end

    @tag init_add: [episodes: {:short, [future: 12, now: 1, past: 1]}]
    test "handles resume cmd", ctx do
      assert %{init_args: init_args, dev_alias: dev_alias, instance: instance} = ctx
      assert %{name: <<_::binary>>} = dev_alias
      assert <<_::binary>> = instance

      server = get_in(init_args, [:instance])
      assert <<_::binary>> = server

      assert {:ok, pid} = GenServer.start_link(Carol.Server, init_args, [])
      assert is_pid(pid) and Process.alive?(pid)
      # NOTE: receive the first noreply for bootstrap
      assert_receive({:noreply, %Carol.State{}}, 200)

      # NOTE: call register/1 on the equipment to trigger a notify
      Alfred.DevAlias.register(dev_alias)
      # NOTE: receive the second noreply for the first tick
      assert_receive({:noreply, %Carol.State{}}, 200)

      # TODO: enhance assertions to check for pause and resumt
      cmd = "resume"
      execute = Alfred.execute(name: server, cmd: cmd)

      assert %Alfred.Execute{rc: :ok, story: %{cmd: ^cmd}} = execute

      status = Alfred.status(server)
      assert %Alfred.Status{story: story} = status
      assert %{notify: "enabled"} = story
    end

    # assert %{init_args: init_args, dev_alias: dev_alias} = ctx
    # assert %{name: <<_::binary>>} = dev_alias
    #
    # server = get_in(init_args, [:instance])
    # assert <<_::binary>> = server
    #
    # assert {:ok, pid} = GenServer.start_link(Carol.Server, init_args, [])
    # assert is_pid(pid) and Process.alive?(pid)
    #
    # # NOTE: call register/1 on the equipment to trigger a notify
    # Alfred.DevAlias.register(dev_alias)
    # assert_receive(%Carol.State{}, 200)
    #
    # # TODO: enhance assertions to check for pause and resumt
    # e1 = Alfred.execute(name: server, cmd: "pause")
    # assert %Alfred.Execute{rc: :ok} = e1
    #
    # s1 = Alfred.status(server)
    # assert %Alfred.Status{rc: :ok} = s1
    #
    # s1 |> tap(fn x -> ["\n", inspect(x, pretty: true)] |> IO.warn() end)
    #
    # e2 = Alfred.execute(name: server, cmd: "resume")
    # assert %Alfred.Execute{rc: :ok} = e2
    #
    # s2 = Alfred.status(server)
    # assert %Alfred.Status{rc: :ok} = s2
  end
end
