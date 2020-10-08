defmodule WorkerLogicTest do
  @moduledoc false

  use Timex
  use ExUnit.Case, async: false

  alias Helen.Worker.Config.Parser
  alias Helen.Worker.{Logic, State}
  alias Helen.Worker.State.Common
  alias Helen.Workers

  @test_file Path.join([__DIR__, "test_config.txt"]) |> Path.expand()
  @test_config_txt File.read!(@test_file)

  def config(:test) do
    assert {:ok, config} = Parser.parse(@test_config_txt)

    make_state(%{opts: config})
  end

  def make_state(map \\ %{}) do
    import DeepMerge, only: [deep_merge: 2]
    import Helen.Time.Helper, only: [utc_now: 0]

    base = %{
      module: __MODULE__,
      server: %{mode: :init, standby_reason: :none},
      logic: %{},
      devices: %{},
      opts: %{},
      timeouts: %{last: :never, count: 0},
      token: make_ref(),
      token_at: utc_now()
    }

    deep_merge(base, map)
  end

  test "can create basic state" do
    assert %{token: token, token_at: token_at} = make_state()

    assert is_reference(token)
    assert %DateTime{} = token_at
  end

  test "can get available modes" do
    state = config(:test)

    # NOTE:  available_modes/1 always returns a sorted list
    assert Logic.available_modes(state) == [:all_stop, :alpha, :beta, :gamma]
  end

  test "can change the token" do
    %{token: initial_token, token_at: initial_token_at} = state = make_state()

    %{token: changed_token, token_at: changed_token_at} =
      Common.change_token(state)

    refute changed_token == initial_token
    refute changed_token_at == initial_token_at
  end

  test "can confirm a mode exists" do
    state = config(:test) |> Logic.confirm_mode_exists(:beta)

    refute Common.faults?(state)
  end

  test "can detect a mode does not exist" do
    state = config(:test) |> Logic.confirm_mode_exists(:foobar)

    refute Common.faults?(state)
    assert Common.faults_get(state, :init) == {:unknown_mode, :foobar}
  end

  test "can perform init" do
    %{logic: %{live: live}} =
      state =
      config(:test)
      |> Logic.init(:alpha)

    refute Common.faults?(state)
    assert %{active_mode: :alpha, steps: steps} = live
    assert %{at_start: %{actions: actions}} = steps

    assert %{worker_name: :air, cmd: :on, for: "PT0.1S", then: :off} ==
             hd(actions)

    assert state[:workers] |> is_map()
  end

  test "can start a mode that does not repeat and has next mode defined" do
    import Helen.Time.Helper, only: [to_duration: 1, to_ms: 1]

    expected_duration = to_duration("PT0.3S")
    mode = :alpha

    state = config(:test) |> Logic.init(mode) |> Logic.start()

    live = State.live_get(state, [])

    assert is_map(live)
    assert State.live_get(state, :active_mode) == mode
    assert %DateTime{} = State.track_get(state, :started_at)
    assert State.live_get(state, :will_finish_in_ms) == to_ms(expected_duration)
    assert %DateTime{} = State.track_step_get(state, :started_at)
    assert %Duration{} = State.track_step_get(state, :elapsed)

    assert %{steps_to_execute: steps_to_execute} =
             state
             |> get_in([:logic, :live, :track])

    assert is_list(steps_to_execute)

    assert %{actions_to_execute: actions_to_execute} =
             get_in(state, [:logic, :live, :track])

    assert actions_to_execute == []

    assert State.track_get(state, :sequence) == [
             :at_start,
             :middle,
             :finally
           ]

    assert State.track_get(state, :steps_to_execute) == [:middle, :finally]

    Process.sleep(1000)

    state =
      Logic.next_action(state) |> Logic.next_action() |> Logic.next_action()

    assert State.track_get(state, :steps_to_execute) == [:finally]

    Process.sleep(1000)

    # confirm the mode finishes
    token = get_in(state, [:token])

    state =
      for _x <- 1..100, reduce: state do
        %{token: state_token} = state when state_token == token ->
          state |> Logic.next_action()

        state ->
          state
      end

    assert Logic.finished?(state, mode)
    # has live been populated with the next mode?
    assert State.active_mode(state) in [:none, :beta]
  end

  test "can start a mode that repeats" do
    mode = :beta

    state = config(:test) |> Logic.init(mode) |> Logic.start()

    live = State.live_get(state, [])

    assert is_map(live)
    assert State.active_mode(state) == mode
    assert %DateTime{} = State.track_get(state, :started_at)
    assert is_nil(State.live_get(state, :will_finish_in_ms))
    assert is_nil(State.live_get(state, :will_finish_by))
    assert State.mode_repeat_until_stopped?(state)

    # confirm the pending acfion has been populated
    assert %{msg_type: msg_type, reply_to: reply_to} =
             State.pending_action(state)

    assert msg_type == :logic
    assert is_pid(reply_to)
    assert reply_to == self()

    state = Logic.next_action(state)
    assert %{} = State.update_elapsed(state)

    # confirm the mode never ends
    for _x <- 1..100, reduce: state do
      %{logic: %{live: %{track: %{active_step: _step}}}} = state ->
        refute Enum.empty?(State.track_get(state, :steps_to_execute))

        assert State.live_get(state, :status) == :running

        state |> Logic.next_action()
    end
  end

  test "can start a mode that holds" do
    mode = :gamma

    state = config(:test) |> Logic.init(mode) |> Logic.start()

    assert Workers.module_cache_complete?(get_in(state, [:workers]))

    assert State.active_mode(state) == mode

    # execute (consume) all the actions
    state = consume_actions(state, 9)

    # original mode should still be active
    assert State.active_mode(state) == mode

    # mode should be marked as holding
    assert Logic.holding?(state)
  end

  test "can get the sequence of the live mode" do
    state = config(:test) |> Logic.init(:alpha) |> Logic.start()

    assert State.mode_sequence(state) == [:at_start, :middle, :finally]
  end

  test "can get command definitions" do
    mode = :alpha

    state = config(:test) |> Logic.init(mode) |> Logic.start()

    cmd = State.cmd_definition(state, :cmd_alpha)

    assert is_map(cmd)
  end

  defp consume_actions(state, count) do
    for _x <- 1..count, reduce: state do
      state -> Logic.next_action(state)
    end
  end
end
