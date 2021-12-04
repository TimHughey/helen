defmodule Should.Be.Tuple do
  @moduledoc """
  Collection of macros for validating `strcuts` in `ExUnit.Case` test
  """

  @doc """
  Asserts when `x` is a tuple then returns `x`

  ```
  assert is_tuple(x), Should.msg(x, "should be tuple")

  x
  ```

  """
  @doc since: "0.6.12"
  defmacro check(x) do
    quote location: :keep, bind_quoted: [x: x] do
      assert is_tuple(x), Should.msg(x, "should be tuple")

      x
    end
  end

  @doc """
  Asserts when `x` is` {:noreply, struct}`, returns `struct`

  ```
  {reply, struct} = Should.Be.Tuple.with_size(x, 3)
  assert reply == :noreply, Should.msg(reply, "should be :noreply")

  Should.Be.struct(struct, want_struct)
  ```

  """
  @doc since: "0.6.14"
  defmacro noreply(x, want_struct) do
    quote location: :keep, bind_quoted: [x: x, want_struct: want_struct] do
      {reply, struct} = Should.Be.Tuple.with_size(x, 2)
      assert reply == :noreply, Should.msg(reply, "should be :noreply")

      Should.Be.struct(struct, want_struct)
    end
  end

  @doc """
  Asserts when `x` is` {:reply, :ok, struct}`, returns `struct`

  ```
  {reply, rc, struct} = Should.Be.Tuple.with_size(x, 3)
  assert reply == :reply, Should.msg(reply, "should be :reply")
  assert rc == :ok, Should.msg(rc, "should be :ok")

  Should.Be.struct(struct, want_struct)
  ```

  """
  @doc since: "0.6.13"
  defmacro reply_ok(x, want_struct) do
    quote location: :keep, bind_quoted: [x: x, want_struct: want_struct] do
      {reply, rc, struct} = Should.Be.Tuple.with_size(x, 3)
      assert reply == :reply, Should.msg(reply, "should be :reply")
      assert rc == :ok, Should.msg(rc, "should be :ok")

      Should.Be.struct(struct, want_struct)
    end
  end

  @doc """
  Asserts when `x` is` {:stop, rc, struct}`, returns `struct`

  ```
  {reply, rc, struct} = Should.Be.Tuple.with_size(x, 3)
  assert reply == :stop, Should.msg(reply, "should be :stop")
  assert rc == rc, Should.msg(rc, "should be", rc)

  Should.Be.struct(struct, want_struct)
  ```

  """
  @doc since: "0.6.13"
  defmacro reply_stop(x, rc, want_struct) do
    quote location: :keep, bind_quoted: [x: x, rc: rc, want_struct: want_struct] do
      {reply, rc, struct} = Should.Be.Tuple.with_size(x, 3)
      assert reply == :stop, Should.msg(reply, "should be :stop")
      assert rc == rc, Should.msg(rc, "should be", rc)

      Should.Be.struct(struct, want_struct)
    end
  end

  @doc """
  Asserts when `x` is a `{rc, val}` tuple and returns val

  ```
  {rc, val} = Should.Be.Tuple.with_size(x, 2)
  assert rc == want_rc, Should.msg(rc, "should be", want_rc)

  val
  ```

  """
  @doc since: "0.6.12"
  defmacro with_rc(x, want_rc) do
    quote location: :keep, bind_quoted: [x: x, want_rc: want_rc] do
      {rc, val} = Should.Be.Tuple.with_size(x, 2)
      assert rc == want_rc, Should.msg(rc, "should be", want_rc)

      val
    end
  end

  @doc """
  Asserts when `x` is a `{rc, binary}` tuple and returns binary

  ```
  {rc, val} = Should.Be.Tuple.with_size(x, 2)
  assert rc == want_rc, Should.msg(rc, "should be", want_rc)
  Should.Contain.binaries(val, want_binary)

  val
  ```

  """
  @doc since: "0.6.12"
  defmacro with_rc_and_binaries(x, want_rc, want_binary) do
    quote location: :keep, bind_quoted: [x: x, want_rc: want_rc, want_binary: want_binary] do
      {rc, val} = Should.Be.Tuple.with_size(x, 2)
      assert rc == want_rc, Should.msg(rc, "should be", want_rc)
      Should.Contain.binaries(val, want_binary)

      val
    end
  end

  @doc """
  Asserts when `x` is a `{rc, binary}` tuple and returns binary

  ```
  {rc, val} = Should.Be.Tuple.with_size(x, 2)
  assert rc == want_rc, Should.msg(rc, "should be", want_rc)
  Should.Be.NonEmpty.list(val)

  # return the list
  val
  ```

  """
  @doc since: "0.6.13"
  defmacro with_rc_and_list(x, want_rc) do
    quote location: :keep, bind_quoted: [x: x, want_rc: want_rc] do
      {rc, val} = Should.Be.Tuple.with_size(x, 2)
      assert rc == want_rc, Should.msg(rc, "should be", want_rc)
      Should.Be.NonEmpty.list(val)

      # return the list
      val
    end
  end

  @doc """
  Asserts when `x` is a `{rc, Ecto.Schema}` tuple and returns schema

  ```
  {rc, schema} = Should.Be.Tuple.with_size(x, 2)
  assert rc == want_rc, Should.msg(rc, "should be", want_rc)
  Should.Be.schema(schema, want_schema)

  # return the schema
  schema

  val
  ```

  """
  @doc since: "0.6.12"
  defmacro with_rc_and_schema(x, want_rc, want_schema) do
    quote location: :keep, bind_quoted: [x: x, want_rc: want_rc, want_schema: want_schema] do
      {rc, schema} = Should.Be.Tuple.with_size(x, 2)
      assert rc == want_rc, Should.msg(rc, "should be", want_rc)
      Should.Be.schema(schema, want_schema)

      # return the schema
      schema
    end
  end

  @doc """
  Asserts when `x` is a `{rc, struct}` tuple and returns struct

  ```
  {rc, struct} = Should.Be.Tuple.with_size(x, 2)
  assert rc == want_rc, Should.msg(rc, "should be", want_rc)
  Should.Be.struct(struct, want_struct)

  # return the struct
  struct
  ```

  """
  @doc since: "0.6.17"
  defmacro with_rc_and_struct(x, want_rc, want_struct) do
    quote location: :keep, bind_quoted: [x: x, want_rc: want_rc, want_struct: want_struct] do
      {rc, struct} = Should.Be.Tuple.with_size(x, 2)
      assert rc == want_rc, Should.msg(rc, "should be", want_rc)
      Should.Be.struct(struct, want_struct)

      # return the struct
      struct
    end
  end

  @doc """
  Asserts when `x` is a tuple with size then returns tuple

  ```
  Should.Be.Tuple(x)
  assert tuple_size(x, size), Should.msg(x, "should be size", size)

  x
  ```

  """
  @doc since: "0.6.12"
  defmacro with_size(x, size) do
    quote location: :keep, bind_quoted: [x: x, size: size] do
      Should.Be.Tuple.check(x)
      assert tuple_size(x) == size, Should.msg(x, "should be size", size)

      x
    end
  end
end
