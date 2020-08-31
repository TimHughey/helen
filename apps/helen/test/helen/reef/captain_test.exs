defmodule ReefCaptainTest do
  @moduledoc false

  use ExUnit.Case

  alias Helen.Config.Parser
  alias Reef.Captain.Server, as: Captain

  @lib_path Path.join([__DIR__, "..", "..", "..", "lib"]) |> Path.expand()
  @config_path Path.join([@lib_path, "reef", "captain", "opts"])
  @config_file Path.join([@config_path, "defaults.txt"])
  @config_txt File.read!(@config_file)

  setup_all do
    %{}
  end

  test "reef Captain creates the server state via init/1" do
    {rc, state, continue} = Captain.init([])

    assert rc == :ok
    assert continue == {:continue, :bootstrap}
    assert is_map(state)
    assert %{token: _, token_at: _} = state
    assert %{module: Captain} = state
    assert %{base: _, workers: _, modes: _} = state[:opts]
  end

  test "can parse default config" do
    state = Parser.parse(@config_txt)

    assert is_map(state[:parser])
    assert Parser.syntax_ok?(state)
  end

  test "can get Captain available modes" do
    modes = Captain.available_modes()
    assert is_list(modes)

    assert modes == [
             :add_salt,
             :dump_water,
             :fill,
             :final_check,
             :keep_fresh,
             :load_water,
             :match_conditions
           ]
  end

  test "reef Captain ignores logic cast messages when msg token != state token" do
    msg = %{token: make_ref()}
    {:ok, state, _continue} = Captain.init([])

    assert {:noreply, %{token: _}, _timeout} =
             Captain.handle_cast({:logic, msg}, state)
  end

  test "roost server ignores logic info messages when the token != state token" do
    msg = %{token: make_ref()}
    {:ok, state, _} = Captain.init([])

    assert {:noreply, %{token: _}, _timeout} =
             Captain.handle_info({:logic, msg}, state)
  end

  test "the truth will set you free" do
    assert true
  end

  # def config(what) do
  #   parsed =
  #     case what do
  #       :roost -> Parser.parse(@config_txt)
  #     end
  #
  #   make_state(%{
  #     opts: get_in(parsed, [:config]),
  #     parser: get_in(parsed, [:parser])
  #   })
  # end
  #
  # def make_state(map \\ %{}) do
  #   import DeepMerge, only: [deep_merge: 2]
  #   import Helen.Time.Helper, only: [utc_now: 0]
  #
  #   base = %{
  #     module: __MODULE__,
  #     server: %{mode: :init, standby_reason: :none},
  #     logic: %{},
  #     devices: %{},
  #     opts: %{},
  #     timeouts: %{last: :never, count: 0},
  #     token: make_ref(),
  #     token_at: utc_now()
  #   }
  #
  #   deep_merge(base, map)
  # end
end
