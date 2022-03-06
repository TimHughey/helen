defmodule RenaTest do
  use ExUnit.Case
  use Rena.TestAid

  @moduletag rena: true, rena_use: true, rena_state: true, rena_server: true

  setup [:init_add]

  describe "Rena.child_spec/3" do
    @tag init_add: [
           equipment: [cmd: "off"],
           sensor_group: [
             name: [temp_f: 6.0],
             name: [temp_f: 5.7],
             name: [temp_f: 5.7],
             name: [temp_f: 5.8],
             name: [rc: :expired],
             valid_when: [valid: 1, total: 3]
           ]
         ]

    test "creates spec when opts == [] and otp_app specified", ctx do
      assert %{init_args: init_args} = ctx

      Application.put_env(:rena, __MODULE__, init_args)

      child_spec = Rena.child_spec(__MODULE__, [], %{otp_app: :rena})

      assert {:ok, pid} = start_supervised(child_spec)
      assert Process.alive?(pid)
    end

    @tag init_add: [
           equipment: [cmd: "off"],
           sensor_group: [name: [temp_f: 6.0], valid_when: [valid: 1, total: 1]]
         ]
    test "creates spec when opts != [] and otp_app not specified", ctx do
      assert %{init_args: init_args} = ctx

      child_spec = Rena.child_spec(__MODULE__, init_args, %{})

      assert {:ok, pid} = start_supervised(child_spec)
      assert Process.alive?(pid)
    end

    @tag init_add: [
           equipment: [cmd: "off"],
           sensor_group: [name: [temp_f: 6.0], valid_when: [valid: 1, total: 1]]
         ]
    test "creates spec when opts == [], otp_app not specified and use opts > 3", ctx do
      assert %{init_args: init_args} = ctx

      child_spec = Rena.child_spec(__MODULE__, [], Enum.into(init_args, %{}))

      assert {:ok, pid} = start_supervised(child_spec)
      assert Process.alive?(pid)
    end
  end

  describe "Rena.__using__/1" do
    @tag init_add: [
           equipment: [cmd: "off"],
           sensor_group: [
             name: [temp_f: 6.0],
             name: [temp_f: 5.7],
             name: [temp_f: 5.7],
             name: [temp_f: 5.8],
             name: [rc: :expired],
             adjust_when: [lower: [gt_mid: 1], raise: [lt_mid: 1]],
             valid_when: [valid: 1, total: 3]
           ]
         ]

    test "provides child_spec/1 and can be started supervised", ctx do
      assert %{init_args: init_args, dev_alias: dev_alias} = ctx

      assert {:ok, pid} = start_supervised({Rena.Use, init_args})
      assert is_pid(pid) and Process.alive?(pid)

      # NOTE: receive the first noreply for bootstrap (confirmed by seen_at: nil)
      assert_receive({:noreply, %Rena{server_name: Rena.Use, seen_at: nil}}, 200)

      # NOTE: call register/1 on the equipment to trigger a notify
      Alfred.DevAlias.register(dev_alias)

      # NOTE: receive the second noreply for the first tick
      assert_receive({:noreply, %Rena{server_name: Rena.Use} = state}, 200)
      assert %{register: pid, seen_at: %DateTime{}, sensor: sensor} = state
      assert %Rena.Sensor{next_action: {:raise, "on"}} = sensor

      # ensure the server wasn't restarted by the Supervisor
      assert Process.alive?(pid)
    end
  end

  describe "Rena.make_state/1" do
    test "handles well-formed args", _ctx do
      name = Alfred.NamesAid.unique("rena")

      assert %{sensors: sensor_names} = Alfred.NamesAid.sensors_add(%{sensors_add: []})
      assert %{name: equipment} = Alfred.NamesAid.new_dev_alias(:equipment, [])

      range = [low: 1.0, high: 12.0, unit: :temp_f]
      valid_when = [valid: 2, total: 4]
      sensor_group = [names: sensor_names, range: range, valid_when: valid_when]

      args_common = [alfred: AlfredSim]
      args = args_common ++ [equipment: equipment, name: name, sensor_group: sensor_group]

      state = Rena.make_state(args)
      assert %Rena{} = state
      assert %{name: ^name, equipment: ^equipment, server_name: nil} = state

      assert %{sensor: %Rena.Sensor{} = sensor} = state
      assert %{names: ^sensor_names, halt_reason: :none, reading_at: nil} = sensor
      assert %{next_action: {:no_change, :none}} = sensor
      assert %{range: new_range, tally: %{}, valid_when: new_valid_when} = sensor

      assert %{high: 12.0, low: 1.0, mid: 6.5, unit: :temp_f} = new_range
      assert ^new_valid_when = Enum.into(valid_when, %{})
    end
  end

  describe "Rena starts supervised" do
    # NOTE:  only two tests are required for starting supervised because
    #        once started no code is executed until receipt of a notify
    @tag init_add: [
           sensor_group: [
             name: [temp_f: 6.0],
             name: [temp_f: 6.1],
             name: [temp_f: 0.5],
             name: [temp_f: 11.1],
             name: [rc: :expired, temp_f: 0]
           ]
         ]
    test "with well-formed init args", ctx do
      assert %{init_args: [_ | _] = init_args} = ctx
      child_spec = Rena.child_spec(__MODULE__, init_args, %{})

      assert {:ok, pid} = start_supervised(child_spec)
      assert is_pid(pid)
      assert Process.alive?(pid)

      state = :sys.get_state(pid)
      assert %Rena{} = state

      pid = GenServer.whereis(__MODULE__)
      assert is_pid(pid)
    end
  end

  describe "Rena.handle_continue/2" do
    @tag init_add: [
           sensor_group: [
             name: [temp_f: 6.0],
             name: [temp_f: 6.1],
             name: [temp_f: 0.5],
             name: [temp_f: 11.1],
             name: [rc: :expired, temp_f: 0]
           ]
         ]
    test "handles :tick", ctx do
      assert %{init_args: init_args} = ctx
      state = Rena.make_state(init_args)
      assert %Rena{} = state

      assert {:noreply, state} = Rena.handle_continue(:bootstrap, state)
      assert {:noreply, state} = Rena.handle_continue(:tick, state)

      assert %{register: pid, ticket: {:ok, _pid}} = state
      assert is_pid(pid)
      assert Process.alive?(pid)
    end
  end
end
