defmodule Should.Be.DateTime do
  @moduledoc """
  Collection of macros for validating DateTimes
  """

  @doc """
  Asserts when `dt1` is greater than `dt2`, returns `dt1`

  ```
  Should.Be.datetime(dt1)
  Should.Be.datetime(dt2)

  assert is_list(want_compare), Should.msg(want_compare, "compare should be a list")
  refute want_compare == [], Should.msg(want_compare, "must have compares to check")

  check = DateTime.compare(dt1, dt2) in want_compare

  assert check, Should.msg({dt1, dt2}, "should be", want_compare)

  # return the first DateTime
  dt1
  dt1
  ```

  """
  @doc since: "0.6.34"
  defmacro compare_in(dt1, dt2, want_compare) do
    quote bind_quoted: [dt1: dt1, dt2: dt2, want_compare: want_compare] do
      Should.Be.datetime(dt1)
      Should.Be.datetime(dt2)

      assert is_list(want_compare), Should.msg(want_compare, "compare should be a list")
      refute want_compare == [], Should.msg(want_compare, "must have compares to check")

      check = DateTime.compare(dt1, dt2) in want_compare

      assert check, Should.msg({dt1, dt2}, "should be", want_compare)

      # return the first DateTime
      dt1
    end
  end

  @doc """
  Asserts when `dt1` is greater than `dt2`, returns `dt1`

  ```
  for dt <- [dt1, dt2], do: Should.Be.struct(dt, DateTime)

  compare = DateTime.compare(dt1, dt2)

  assert compare == :gt, Should.msg(dt1, "should be greater than", dt2)

  # return the first DateTime
  dt1
  ```

  """
  @doc since: "0.6.21"
  defmacro greater(dt1, dt2) do
    quote bind_quoted: [dt1: dt1, dt2: dt2] do
      for dt <- [dt1, dt2], do: Should.Be.struct(dt, DateTime)

      compare = DateTime.compare(dt1, dt2)

      assert compare == :gt, Should.msg(dt1, "should be greater than", dt2)

      # return the first DateTime
      dt1
    end
  end

  @doc """
  Asserts when `dt1` is equal to `dt2`, returns `dt1`

  ```
  for dt <- [dt1, dt2], do: Should.Be.struct(dt, DateTime)

  compare = DateTime.compare(dt1, dt2)

  assert compare == :eq, Should.msg(dt1, "should be equal to", dt2)

  # return the first DateTime
  dt1
  ```

  """
  @doc since: "0.6.21"
  defmacro equal(dt1, dt2) do
    quote bind_quoted: [dt1: dt1, dt2: dt2] do
      for dt <- [dt1, dt2], do: Should.Be.struct(dt, DateTime)

      compare = DateTime.compare(dt1, dt2)

      assert compare == :eq, Should.msg(dt1, "should be equal to", dt2)

      # return the first DateTime
      dt1
    end
  end

  @doc """
  Asserts when `dt1` is less than `dt2`, returns `dt1`

  ```
  for dt <- [dt1, dt2], do: Should.Be.struct(dt, DateTime)

  compare = DateTime.compare(dt1, dt2)

  assert compare == :lt, Should.msg(dt1, "should be less than", dt2)

  # return the first DateTime
  dt1
  ```

  """
  @doc since: "0.6.34"
  defmacro less(dt1, dt2) do
    quote bind_quoted: [dt1: dt1, dt2: dt2] do
      for dt <- [dt1, dt2], do: Should.Be.struct(dt, DateTime)

      compare = DateTime.compare(dt1, dt2)

      assert compare == :lt, Should.msg(dt1, "should be less than", dt2)

      # return the first DateTime
      dt1
    end
  end

  @doc """
  Asserts when `dt1` is __near__ `dt2`

  ```
  for dt <- [dt1, dt2], do: Should.Be.struct(dt, DateTime)

  compare = DateTime.compare(dt1, dt2)

  assert compare == :eq, Should.msg(dt1, "should be equal to", dt2)

  # return the first DateTime
  dt1
  ```

  """
  @doc since: "0.6.25"
  defmacro near(dt1, dt2) do
    quote bind_quoted: [dt1: dt1, dt2: dt2] do
      for dt <- [dt1, dt2], do: Should.Be.struct(dt, DateTime)

      dt_after = DateTime.add(dt2, -750, :millisecond)
      dt_before = Timex.shitf(dt2, 750, :milliseconds)

      in_range = [DateTime.compare(dt1, dt_after), DateTime.compare(dt1, dt_before)]

      assert in_range == [:gt, :lt], Should.msg(dt1, "should be 'near'", dt2)

      # return the first DateTime
      dt1
    end
  end
end
