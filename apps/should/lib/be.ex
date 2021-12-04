defmodule Should.Be do
  @moduledoc """
  Collection of macros for validating basic types
  """

  @doc """
  Asserts when `pid` is alive

  ```
  assert Process.alive?(pid), Should.msg(pid, "should be alive")

  # return the pid
  pid
  ```

  """
  @doc since: "0.6.13"
  defmacro alive(pid) do
    quote location: :keep, bind_quoted: [pid: pid] do
      assert Process.alive?(pid), Should.msg(pid, "should be alive")

      # return the pid
      pid
    end
  end

  @doc """
  Asserts `x` when `x` is a function returns true or `x` is true then returns `x`

  ```
  if is_function(x) do
    assert x.(), Should.msg(x, "should be asserted")
  else
    assert x, Should.msg(x, "should be asserted")
  end

  # return asserted
  x
  ```

  """
  @doc since: "0.6.12"
  defmacro asserted(x) do
    quote location: :keep, bind_quoted: [x: x] do
      if is_function(x) do
        assert x.(), Should.msg(x, "should be asserted")
      else
        assert x, Should.msg(x, "should be asserted")
      end

      # return asserted
      x
    end
  end

  @doc """
  Asserts when `x` is binary then returns verified binary

  ```
  assert is_binary(x), Should.msg(x, "should be a binary")

  # return verified binary
  x
  ```

  """
  @doc since: "0.6.12"
  defmacro binary(x) do
    quote location: :keep, bind_quoted: [x: x] do
      assert is_binary(x), Should.msg(x, "should be a binary")

      # return verified binary
      x
    end
  end

  @doc """
  Asserts when `x` is equal to `y`

  ```
  assert x == y, Should.msg(x, "should be equal", y)

  # return equals
  x
  ```

  """
  @doc since: "0.6.21"
  defmacro equal(x, y) do
    quote location: :keep, bind_quoted: [x: x, y: y] do
      assert x == y, Should.msg(x, "should be equal", y)

      # return equals
      x
    end
  end

  @doc """
  Asserts when `x` is a list

  ```
  assert is_list(x), Should.msg(x, "should be a list")
  # return the verified list
  x
  ```
  """
  @doc since: "0.6.12"
  defmacro list(x) do
    quote location: :keep, bind_quoted: [x: x] do
      assert is_list(x), Should.msg(x, "should be a list")
      # return the verified list
      x
    end
  end

  @doc """
  Asserts when `lhs` is a match to `rhs` then returns `rhs`

  ```
  assert match?(^lhs, rhs), Should.msg(lhs, "should match", lhs)
  ```
  """
  @doc since: "0.2.6"
  defmacro match(lhs, rhs) do
    quote location: :keep, bind_quoted: [lhs: lhs, rhs: rhs] do
      assert match?(^lhs, rhs), Should.msg(lhs, "should match", lhs)

      rhs
    end
  end

  @doc """
  Asserts when `x` is a map then returns the verified map

  ```
  assert is_map(x), Should.msg(x, "should be a map")
  # return the verified map
  x
  ```
  """
  @doc since: "0.6.12"
  defmacro map(x) do
    quote location: :keep, bind_quoted: [x: x] do
      assert is_map(x), Should.msg(x, "should be a map")
      # return the verified map
      x
    end
  end

  @doc """
  Asserts when `x` is `:ok`

  ```
  assert x == :ok, Should.msg(x, "should be :ok")
  # return the verified map
  x
  ```
  """
  @doc since: "0.6.13"
  defmacro ok(x) do
    quote location: :keep, bind_quoted: [x: x] do
      assert x == :ok, Should.msg(x, "should be :ok")
      # return the verified map
      x
    end
  end

  @doc """
  Asserts when `x` is a pid, then returns the pid

  ```
  assert is_map(x), Should.msg(x, "should be a map")
  # return the verified map
  x
  ```
  """
  @doc since: "0.6.13"
  defmacro pid(x) do
    quote location: :keep, bind_quoted: [x: x] do
      assert is_pid(x), Should.msg(x, "should be a pid")

      # return the pid
      x
    end
  end

  @doc """
  Asserts when `x` is a schema of `want`

  ```
  alias Ecto.Schema.Metadata

  meta = Should.Be.Struct.with_key(x, named, :__meta__)
  Should.Be.Struct.with_key_value(meta, Metadata, :schema, named)

  # return verified schema
  x
  ```
  """
  @doc since: "0.2.6"
  defmacro schema(x, named) do
    quote location: :keep, bind_quoted: [x: x, named: named] do
      alias Ecto.Schema.Metadata

      meta = Should.Be.Struct.with_key(x, named, :__meta__)
      Should.Be.Struct.with_key_value(meta, Metadata, :schema, named)

      # return verified schema
      x
    end
  end

  @doc """
  Asserts when `x` is a struct with name `named` then returns verified struct

  ```
  assert is_struct(x), Should.msg(x, "should be a struct")
  assert x.__struct__ == named, Should.msg(x, "should be struct", named)

  # return verified struct
  x
  ```
  """
  @doc since: "0.2.6"
  defmacro struct(x, named) do
    quote location: :keep, bind_quoted: [x: x, named: named] do
      assert is_struct(x), Should.msg(x, "should be a struct")
      assert x.__struct__ == named, Should.msg(x, "should be struct", named)

      # return verified struct
      x
    end
  end
end
