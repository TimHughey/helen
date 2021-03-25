defmodule GenDeviceWorkerTest do
  @moduledoc false

  use ExUnit.Case

  alias Helen.Worker.State.Common
  alias GenDevice.{Logic, State}

  setup_all do
    state = %{device_name: "mixtank pump"}
    action = %{cmd: :on, worker_cmd: :on, reply_to: self()}
    Logic.init_inflight(state, action, self(), make_ref())
  end

  describe "GenDevice State Test" do
    setup state do
      Map.merge(state, %{
        inflight: %{action: %{notify: %{at_start: true, at_finish: true}}}
      })
    end

    test "can detect notify at_start in action", state do
      assert State.notify?(state, :at_start)
    end
  end

  describe "GenDevice Worker Test" do
    setup state do
      state
    end

    test "can initialize an action", state do
      assert State.action_get(state, :cmd) == :on
      assert State.reply_to(state) |> is_pid()
      assert State.msg_ref(state) |> is_reference()
      assert State.msg_type(state) |> is_atom()
      assert State.inflight_status(state) == :received
    end

    test "can execute an action without a run for duration", state do
      # NOTE: state from the context is already initialized
      state = Logic.next_status(state)

      assert State.inflight_status(state) == :finished
    end

    test "can execute an action with all options", _state do
      import Helen.Time.Helper, only: [to_duration: 1]

      state = %{device_name: "mixtank pump", module: __MODULE__}

      action = %{
        msg_type: :test,
        cmd: :on,
        worker_cmd: :on,
        notify: %{at_start: true, at_finish: true},
        for: to_duration("PT0.001S")
      }

      state =
        Logic.init_inflight(state, action, self(), :test)
        |> Logic.next_status()

      assert State.inflight_status(state) == :running
      assert State.inflight_get(state, :run_for_timer) |> is_reference()

      assert_receive {:test, %{via_msg_at: :at_start, via_msg: true}}, 1000
      assert_receive {:run_for, _action} = msg, 1000

      {rc, state, _continue} = Logic.handle_info(msg, state)

      assert rc == :noreply
      assert State.inflight_status(state) == :finished
      assert %{status: :ready} == Logic.status(state)

      assert_receive {:test, %{via_msg_at: :at_finish, via_msg: true}}, 1000
    end

    test "handle_action() changes the token", state do
      state = State.inflight_status(state, :received)

      state_token1 = Common.token(state)
      inflight_token1 = State.inflight_token(state)

      assert state_token1 == inflight_token1

      action = %{cmd: :on, worker_cmd: :on, reply_to: self(), for: "PT2M"}

      {:reply, {:ok, %{status: :running}}, new_state, _timeout} =
        Logic.handle_action(action, {self(), make_ref()}, state)

      state_token2 = Common.token(new_state)
      inflight_token2 = State.inflight_token(new_state)

      assert state_token2 == inflight_token2
      refute state_token1 == inflight_token2
    end
  end
end
