defmodule LightsLogicTest do
  use ExUnit.Case
  import GardenTestHelpers, only: [make_state: 1, pretty: 1]

  @moduletag :logic

  def setup_ctx(args) do
    {rc, s} = make_state(args)

    assert :ok == rc, "state creation failed#{pretty(s)}"

    %{state: s}
  end

  setup ctx do
    args = get_in(ctx, [:state_args]) || :default

    {:ok, setup_ctx(args)}
  end

  test "can create list of active control maps", %{state: s} do
    s = Lights.Logic.run(s)

    cmaps = get_in(s, [:ctrl_maps])

    assert is_list(cmaps), ":ctrl_maps should be a list#{pretty(s)}"
    refute cmaps == [], ":ctrl_maps should not be empty#{pretty(s)}"
  end
end
