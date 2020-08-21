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
      server: %{mode: :init, standby_reason: :none},
      devices: %{},
      stage: %{},
      live: %{},
      faults: %{init: :ok},
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

  test "can perform the init_precheck" do
    state = config(:roost) |> Logic.init_precheck(:dance_with_me)

    assert %{stage: %{mode: :dance_with_me, dance_with_me: %{}}} = state
  end

  test "can perform init_mode" do
    state =
      config(:reef)
      |> Logic.init_precheck(:fill)
      |> Logic.init_mode()

    modes = get_in(state, [:stage, :opts, :modes])
    mode = get_in(state, [:stage, :mode])
    actions = get_in(state, [:stage, :fill, :steps, :finally, :actions])

    assert is_map(modes)
    assert :fill == mode

    assert [
             %{cmd: :off, device: :air, float: nil},
             %{cmd: :off, device: :rodi, float: nil}
           ] == actions
  end
end
