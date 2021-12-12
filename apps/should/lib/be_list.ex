defmodule Should.Be.List do
  @moduledoc """
  Collection of macros for validating `List` in `ExUnit.Case` tests
  """

  # @doc """
  # Asserts when is `List`
  #
  # ```
  # assert is_list(x), Should.msg(x, "should be a list")
  # ```
  #
  # """
  # @doc since: "0.6.12"
  # defmacro check(x) do
  #   quote location: :keep, bind_quoted: [x: x] do
  #     assert is_list(x), Should.msg(x, "should be a list")
  #   end
  # end

  @doc """
  Asserts when `x` is empty `List`

  ```
  Should.Be.list(x)
  assert length(x) == 0, Should.msg(x, "should be empty")
  ```
  """
  @doc since: "0.6.26"
  defmacro empty(x) do
    quote location: :keep, bind_quoted: [x: x] do
      Should.Be.list(x)
      assert length(x) == 0, Should.msg(x, "should be empty")
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
  Asserts when `x` is `List` with `key`, returns a list of the key/val

  ```
  list = Should.Be.list(x)

  assert is_atom(key), Should.msg(key, "should be an atom")

  {wanted, _} = Keyword.split(list, [key])

  Should.Be.NonEmpty.list(wanted)

  # return a list of the wanted key/value
  wanted
  ```

  """
  @doc since: "0.6.24"
  defmacro with_key(x, key) do
    quote location: :keep, bind_quoted: [x: x, key: key] do
      list = Should.Be.list(x)

      assert is_atom(key), Should.msg(key, "should be an atom")

      {wanted, _} = Keyword.split(list, [key])

      Should.Be.NonEmpty.list(wanted)

      # return a list of the wanted key/value
      wanted
    end
  end

  @doc """
  Asserts when `x` is `List` is `length`

  ```
  list = Should.Be.list(x)

  for key <- keys, reduce: [] do
    acc -> [Should.Be.List.with_key(list, key) | acc]
  end
  # returns a list of the wanted keys
  |> List.flatten()
  ```

  """
  @doc since: "0.6.24"
  defmacro with_keys(x, keys) do
    quote location: :keep, bind_quoted: [x: x, keys: keys] do
      list = Should.Be.list(x)

      for key <- keys, reduce: [] do
        acc -> [Should.Be.List.with_key(list, key) | acc]
      end
      # returns a list of the wanted keys
      |> List.flatten()
    end
  end

  @doc """
  Asserts when `x` is `List` is `length`

  ```
  list = Should.Be.list(x)
  assert length(x) == length, Should.msg(x, "should be length", length)

  # for single entry lists return the entry, else the whole list
  if(length == 1), do: List.first(x), else: x
  ```

  """
  @doc since: "0.6.12"
  defmacro with_length(x, length) do
    quote location: :keep, bind_quoted: [x: x, length: length] do
      list = Should.Be.list(x)
      assert length(x) == length, Should.msg(x, "should be length", length)

      # for single entry lists return the entry, else the whole list
      if length == 1, do: List.first(x), else: x
    end
  end
end
