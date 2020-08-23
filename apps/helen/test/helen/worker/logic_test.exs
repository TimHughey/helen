defmodule WorkerLogicTest do
  @moduledoc false

  use Timex
  use ExUnit.Case

  alias Helen.Config.Parser
  alias Roost.Logic

  @reef_config_txt Path.join([__DIR__, "reef_config.txt"]) |> File.read!()
  @roost_config_txt Path.join([__DIR__, "roost_config.txt"]) |> File.read!()

  def config(what) do
    parsed =
      case what do
        :reef -> Parser.parse(@reef_config_txt)
        :roost -> Parser.parse(@roost_config_txt)
      end

    make_state(%{
      opts: get_in(parsed, [:config]),
      parser: get_in(parsed, [:parser])
    })
  end

  def make_state(map \\ %{}) do
    import DeepMerge, only: [deep_merge: 2]
    import Helen.Time.Helper, only: [utc_now: 0]

    base = %{
      module: __MODULE__,
      server: %{mode: :init, standby_reason: :none},
      devices: %{},
      faults: %{},
      finished_modes: %{},
      live: %{},
      opts: %{},
      stage: %{},
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

  test "can parse test configs" do
    config_txt = [@reef_config_txt, @roost_config_txt]

    for txt <- config_txt do
      state = Parser.parse(txt)

      assert %{parser: %{unmatched: %{lines: [], count: 0}}} = state
    end
  end

  test "can get available modes" do
    for x <- [config(:reef), config(:roost)] do
      modes = Logic.available_modes(x)
      assert is_list(modes) and length(modes) > 2
    end
  end

  test "can change the token" do
    %{token: initial_token, token_at: initial_token_at} = state = make_state()

    %{token: changed_token, token_at: changed_token_at} =
      Logic.change_token(state)

    refute changed_token == initial_token
    refute changed_token_at == initial_token_at
  end

  test "can confirm a mode exists" do
    state = config(:roost) |> Logic.confirm_mode_exists(:dance_with_me)

    assert is_nil(get_in(state, [:faults, :init]))
  end

  test "can detect a mode does not exist" do
    state = config(:roost) |> Logic.confirm_mode_exists(:foobar)

    assert get_in(state, [:faults, :init]) == {:unknown_mode, :foobar}
  end

  test "can perform init_mode" do
    %{stage: stage} =
      state =
      config(:reef)
      |> Logic.init_mode(:fill)

    assert %{active_mode: :fill, steps: steps} = stage |> Map.drop([:opts])
    assert %{at_start: %{actions: actions}} = steps
    assert %{device: :rodi, cmd: :on} = hd(actions)
    refute get_in(state, [:faults, :init])
  end

  test "can start a mode that does not repeat" do
    import Helen.Time.Helper, only: [to_duration: 1, to_ms: 1]

    expected_duration = to_duration("PT5H15M")
    mode = :fill

    state = config(:reef) |> Logic.init_mode(mode) |> Logic.start_mode()

    stage = Logic.stage_get(state, [])
    live = Logic.live_get(state, [])

    assert is_map(stage) and is_map(live)
    assert Enum.empty?(stage)
    assert Logic.live_get(state, :active_mode) == mode
    assert %DateTime{} = Logic.mode_track_get(state, :started_at)
    assert Logic.live_get(state, :will_finish_in_ms) == to_ms(expected_duration)

    assert Logic.mode_track_get(state, :steps_to_execute) == [
             :at_start,
             :main,
             :topoff,
             :finally
           ]
  end

  test "can start a mode that repeats" do
    mode = :keep_fresh

    state = config(:reef) |> Logic.init_mode(mode) |> Logic.start_mode()

    stage = Logic.stage_get(state, [])
    live = Logic.live_get(state, [])

    assert is_map(stage) and is_map(live)
    assert Enum.empty?(stage)
    assert Logic.live_get(state, :active_mode) == mode
    assert %DateTime{} = Logic.mode_track_get(state, :started_at)
    assert is_nil(Logic.live_get(state, :will_finish_in_ms))
    assert is_nil(Logic.live_get(state, :will_finish_by))
    assert Logic.mode_repeat_until_stopped?(state)
  end

  test "can get the sequence of the live mode" do
    state = config(:reef) |> Logic.init_mode(:fill) |> Logic.start_mode()

    assert Logic.live_get_mode_sequence(state) == [
             :at_start,
             :main,
             :topoff,
             :finally
           ]
  end
end
