defmodule Should.Be.List do
  @moduledoc """
  Collection of macros for validating `List` in `ExUnit.Case` tests
  """

  @doc """
  Asserts when is `List`

  ```
  assert is_list(x), Should.msg(x, "should be a list")
  ```

  """
  @doc since: "0.6.12"
  defmacro check(x) do
    quote location: :keep, bind_quoted: [x: x] do
      assert is_list(x), Should.msg(x, "should be a list")
    end
  end

  @doc """
  Asserts when `list` contains one or more `schemas`

  ```
  list = Should.Be.NonEmpty.list(x)

  for item <- list do
    Should.Be.schema(item, schema)
  end

  # return validated list
  list
  ```

  """
  @doc since: "0.6.12"
  defmacro of_schemas(x, schema) do
    quote location: :keep, bind_quoted: [x: x, schema: schema] do
      list = Should.Be.NonEmpty.list(x)

      for item <- list do
        Should.Be.schema(item, schema)
      end

      # return validated list
      list
    end
  end

  @doc """
  Asserts when `list` contains one or more `structs`

  ```
  list = Should.Be.NonEmpty.list(x)

  for item <- list do
    Should.Be.struct(item, struct)
  end

  # return validated list
  list
  ```

  """
  @doc since: "0.6.12"
  defmacro of_structs(x, struct) do
    quote location: :keep, bind_quoted: [x: x, struct: struct] do
      list = Should.Be.NonEmpty.list(x)

      for item <- list do
        Should.Be.struct(item, struct)
      end

      # return validated list
      list
    end
  end

  @doc """
  Asserts when `x` is `List` and `Should.Contain.kv_pairs/2`

  ```
  list = Should.Be.list(x)
  Should.Contain.kv_pairs(x, kv_pairs)

  # return validated list
  list
  ```

  """
  @doc since: "0.6.12"
  defmacro with_all_key_value(x, kv_pairs) do
    quote location: :keep, bind_quoted: [x: x, kv_pairs: kv_pairs] do
      list = Should.Be.list(x)
      Should.Contain.kv_pairs(x, kv_pairs)

      # return validated list
      list
    end
  end

  @doc """
  Asserts when `x` is `List` is `length`

  ```
  list =  Should.Be.list(c)
  assert length(x) == length, Should.msg(x, "should be length", length)

  # return list
  list
  ```

  """
  @doc since: "0.6.12"
  defmacro with_length(x, length) do
    quote location: :keep, bind_quoted: [x: x, length: length] do
      list = Should.Be.list(x)
      assert length(x) == length, Should.msg(x, "should be length", length)

      # return list
      list
    end
  end
end
