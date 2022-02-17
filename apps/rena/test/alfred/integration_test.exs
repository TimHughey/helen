defmodule Reana.ExecuteCmd.Test do
  use ExUnit.Case, async: true
  use Rena.TestAid

  @moduletag rena: true, rena_alfred_integration: true

  setup [:init_add]

  describe "Rena.execute_cmd/2" do
    @tag init_add: [
           sensor_group: [
             name: [temp_f: 6.0],
             name: [temp_f: 6.1],
             name: [temp_f: 0.5],
             name: [temp_f: 11.1],
             name: [rc: :expired, temp_f: 0]
           ]
         ]
    test "handles restart cmd", ctx do
      assert %{init_args: init_args, dev_alias: dev_alias} = ctx
      assert %{name: <<_::binary>>} = dev_alias

      server = get_in(init_args, [:name])
      assert <<_::binary>> = server

      assert {:ok, pid} = GenServer.start_link(Rena, init_args, [])
      assert is_pid(pid) and Process.alive?(pid)
      # NOTE: receive the first noreply for bootstrap
      assert_receive({:noreply, %Rena{}}, 200)

      # NOTE: call register/1 on the equipment to trigger a notify
      Alfred.DevAlias.register(dev_alias)
      # NOTE: receive the second noreply for the first tick
      assert_receive({:noreply, %Rena{}}, 200)

      cmd = "restart"
      execute = Alfred.execute(name: server, cmd: cmd)
      assert %Alfred.Execute{rc: :ok, story: %{cmd: ^cmd}} = execute

      Process.sleep(100)
      refute Process.alive?(pid)
    end

    @tag init_add: [
           sensor_group: [
             name: [temp_f: 6.0],
             name: [temp_f: 6.1],
             name: [temp_f: 0.5],
             name: [temp_f: 11.1],
             name: [rc: :expired, temp_f: 0]
           ]
         ]
    test "handles pause cmd", ctx do
      assert %{init_args: init_args, dev_alias: dev_alias} = ctx
      assert %{name: <<_::binary>>} = dev_alias

      server = get_in(init_args, [:name])
      assert <<_::binary>> = server

      assert {:ok, pid} = GenServer.start_link(Rena, init_args, [])
      assert is_pid(pid) and Process.alive?(pid)
      # NOTE: receive the first noreply for bootstrap
      assert_receive({:noreply, %Rena{}}, 200)

      # NOTE: call register/1 on the equipment to trigger a notify
      Alfred.DevAlias.register(dev_alias)
      # NOTE: receive the second noreply for the first tick
      assert_receive({:noreply, %Rena{}}, 200)

      cmd = "pause"
      execute = Alfred.execute(name: server, cmd: cmd)

      assert %Alfred.Execute{rc: :ok, story: %{cmd: ^cmd}} = execute

      status = Alfred.status(server)
      assert %Alfred.Status{story: story} = status
      assert %{notify: "disabled"} = story
    end

    @tag init_add: [
           sensor_group: [
             name: [temp_f: 6.0],
             name: [temp_f: 6.1],
             name: [temp_f: 0.5],
             name: [temp_f: 11.1],
             name: [rc: :expired, temp_f: 0]
           ]
         ]
    test "handles resume cmd", ctx do
      assert %{init_args: init_args, dev_alias: dev_alias} = ctx
      assert %{name: <<_::binary>>} = dev_alias

      server = get_in(init_args, [:name])
      assert <<_::binary>> = server

      assert {:ok, pid} = GenServer.start_link(Rena, init_args, [])
      assert is_pid(pid) and Process.alive?(pid)
      # NOTE: receive the first noreply for bootstrap
      assert_receive({:noreply, %Rena{}}, 200)

      # NOTE: call register/1 on the equipment to trigger a notify
      Alfred.DevAlias.register(dev_alias)
      # NOTE: receive the second noreply for the first tick
      assert_receive({:noreply, %Rena{}}, 200)

      # TODO: enhance assertions to check for pause and resumt
      cmd = "resume"
      execute = Alfred.execute(name: server, cmd: cmd)

      assert %Alfred.Execute{rc: :ok, story: %{cmd: ^cmd}} = execute

      status = Alfred.status(server)
      assert %Alfred.Status{story: story} = status
      assert %{notify: "enabled"} = story
    end
  end
end
