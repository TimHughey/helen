defmodule Should.Be.DateTime do
  @moduledoc """
  Collection of macros for validating DateTimes
  """

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
    quote location: :keep, bind_quoted: [dt1: dt1, dt2: dt2] do
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
    quote location: :keep, bind_quoted: [dt1: dt1, dt2: dt2] do
      for dt <- [dt1, dt2], do: Should.Be.struct(dt, DateTime)

      compare = DateTime.compare(dt1, dt2)

      assert compare == :eq, Should.msg(dt1, "should be equal to", dt2)

      # return the first DateTime
      dt1
    end
  end
end
