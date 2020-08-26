defmodule WorkerLogicStateAccessTest do
  @moduledoc false

  use ExUnit.Case
  alias Roost.Logic

  test "can track a step key/value" do
    state = %{live: %{active_step: :foo, track: %{}}}

    %{live: %{active_step: :foo, track: %{steps: %{foo: %{key1: :val1}}}}} =
      Logic.track_step_put(state, :key1, :val1)
  end
end
