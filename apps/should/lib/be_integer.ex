defmodule Should.Be.Integer do
  @moduledoc """
  Collection of macros for validating integers
  """

  @doc """
  Asserts when `val` is an integer within +/- `percent`

  ```
  assert is_integer(val), Should.msg(val, "should be an integer")
  assert is_integer(want_val), Should.msg(want_val, "wanted value should be an integer")
  assert is_integer(percent), Should.msg(percent, "percent should be an integer")

  low = want_val * (percent / 100)
  high = want_val * (percent / 100)

  assert val >= low, Should.msg(val, "should be greater than or equal to", low)
  assert val <= high, Should.msg(val, "should be less than or equal to", high)

  # return validated value
  val
  ```
  """
  @doc since: "0.2.25"
  defmacro near(val, want_val, percent) do
    quote location: :keep, bind_quoted: [val: val, want_val: want_val, percent: percent] do
      assert is_integer(val), Should.msg(val, "should be an integer")
      assert is_integer(want_val), Should.msg(want_val, "wanted value should be an integer")
      assert is_integer(percent), Should.msg(percent, "percent should be an integer")

      low = val - want_val * (percent / 100)
      high = val + want_val * (percent / 100)

      assert val >= low, Should.msg(val, "should be greater than or equal to", low)
      assert val <= high, Should.msg(val, "should be less than or equal to", high)

      # return validated value
      val
    end
  end

  @doc """
  Asserts when `int` is a positive integer

  ```
  assert is_integer(int), Should.msg(int, "should be an integer")
  assert int > 0, Should.msg(int, "should be greater than zero")

  # return the integer
  int
  ```

  """
  @doc since: "0.6.25"
  defmacro positive(int) do
    quote location: :keep, bind_quoted: [int: int] do
      assert is_integer(int), Should.msg(int, "should be an integer")
      assert int > 0, Should.msg(int, "should be greater than zero")

      # return the integer
      int
    end
  end
end
