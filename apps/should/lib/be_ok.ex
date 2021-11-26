defmodule Should.Be.Ok do
  @moduledoc """
  Collection of macros for validating `:ok` terms
  """

  @doc """
  Asserts when `x` is `{:ok, pid`}` then returns pid

  ```
  {rc, pid} = Should.Be.Tuple.with_size(x, 2)
  assert rc == :ok, Should.msg(rc, "should be equal to", :ok)

  Should.Be.pid(pid)
  ```

  """
  @doc since: "0.6.12"
  defmacro tuple_with_pid(x) do
    quote location: :keep, bind_quoted: [x: x] do
      {rc, pid} = Should.Be.Tuple.with_size(x, 2)
      assert rc == :ok, Should.msg(rc, "should be equal to", :ok)

      Should.Be.pid(pid)
    end
  end

  @doc """
  Asserts when tuple is `{:ok, val}` then returns `val`

  ```
  {rc, val} = Should.Be.Tuple.with_size(x, 2)
  assert rc == :ok, Should.msg(rc, "should be equal to", :ok)

  val
  ```

  """
  @doc since: "0.6.12"
  defmacro tuple_with_struct(x, want_struct) do
    quote location: :keep, bind_quoted: [x: x, want_struct: want_struct] do
      {rc, val} = Should.Be.Tuple.with_size(x, 2)
      assert rc == :ok, Should.msg(rc, "should be equal to", :ok)

      val
    end
  end
end