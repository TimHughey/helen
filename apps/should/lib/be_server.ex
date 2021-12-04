defmodule Should.Be.Server do
  @moduledoc """
  Collection of macros for validating GenServers
  """

  @doc """
  Asserts when `pid` is a GenServer and answers `:sys.get_state/1` with a `State`

  ```
  Should.Be.pid(pid)
  assert Process.alive?(pid), Should.msg(pid, "should be alive")

  state = :sys.get_state(pid)

  assert is_struct(state), Should.msg(state, "should be a struct")

  suffix = state.__struct__ |> Module.split() |> List.last()

  Module.concat([suffix])
  |> Should.Be.equal(suffix, State)

  # return the state
  state
  ```

  """
  @doc since: "0.6.22"
  defmacro with_state(pid) do
    quote location: :keep, bind_quoted: [pid: pid] do
      Should.Be.pid(pid)
      assert Process.alive?(pid), Should.msg(pid, "should be alive")

      state = :sys.get_state(pid)

      assert is_struct(state), Should.msg(state, "should be a struct")

      suffix = state.__struct__ |> Module.split() |> List.last()

      Module.concat([suffix])
      |> Should.Be.equal(State)

      # return the state
      state
    end
  end
end
