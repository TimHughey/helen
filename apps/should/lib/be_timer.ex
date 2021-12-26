defmodule Should.Be.Timer do
  @moduledoc """
  Collection of macros for validating `Process.send_after/3` timers
  """

  @doc """
  Asserts when `ref` is a `timer` with `remaining ms` near `want_ms`

  > Use `delta` to control allowed difference

  ```
  Should.Be.reference(ref)

  left_ms = Process.read_timer(ref)

  refute is_nil(left_ms), Should.msg(ref, "does not reference a timer")
  assert_in_delta left_ms, want_ms, delta, Should.msg(left_ms, "should be close to \#{want_ms}")

  # return ref
  ref
  ```
  """
  @doc since: "0.6.23"
  defmacro with_ms(ref, want_ms, delta \\ 199) do
    quote bind_quoted: [ref: ref, want_ms: want_ms, delta: delta] do
      Should.Be.reference(ref)

      left_ms = Process.read_timer(ref)

      refute is_nil(left_ms), Should.msg(ref, "does not reference a timer")
      assert_in_delta left_ms, want_ms, delta, Should.msg(left_ms, "should be close to #{want_ms}")

      # return ref
      ref
    end
  end
end
