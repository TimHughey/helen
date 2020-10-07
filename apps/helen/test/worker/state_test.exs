defmodule WorkerLogicStateTest do
  @moduledoc false

  use ExUnit.Case
  alias Helen.Worker.State

  test "can put an init fault and detect it" do
    # init_fault_put/2 will create underlying maps if they don't exist
    # so we pass an empty map as the state
    state = State.init_fault_put(%{}, %{hello: :doctor})

    assert %{
             logic: %{
               faults: %{
                 init: %{hello: :doctor}
               },
               finished: %{},
               live: %{}
             }
           } == state
  end
end
