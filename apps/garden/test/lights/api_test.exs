defmodule LightsApiTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import GardenTestHelpers, only: [pretty: 1]

  setup_all ctx do
    import Lights.Server, only: [initial_state: 1]

    s = initial_state([])

    server_mod = s[:mod]

    wait_for_start = fn ->
      for _i <- 1..1000, reduce: false do
        false ->
          Process.sleep(1)
          server_mod.alive?()

        true ->
          true
      end
    end

    assert wait_for_start.()

    client_mod = [Module.split(server_mod) |> hd()] |> Module.concat()

    {:ok, Map.merge(%{mod: client_mod}, ctx)}
  end

  test "can invoke Lights.timeouts/0", %{mod: mod} do
    timeouts = mod.timeouts()

    fail = "should be :none or a map#{pretty(timeouts)}"
    assert timeouts == :none or is_map(timeouts), fail
  end

  test "can invoke Lights.alive?/0", %{mod: mod} do
    assert mod.alive?()
  end

  test "can invoke Lights.config/0", %{mod: mod} do
    assert is_map(mod.config())
    assert mod.config(name: NotAModule) == :no_server
  end
end
