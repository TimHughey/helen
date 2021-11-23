defmodule Should.Be.Struct do
  @moduledoc """
  Collection of macros for validating `structs` in `ExUnit.Case` tests
  """

  @doc """
  Asserts when is struct and struct name matches

  ```
  assert is_struct(x), Should.msg(x, "should be a struct")
  assert x.__struct__ == want_struct, Should.msg(x, "should be struct", want_struct)
  ```

  """
  @doc since: "0.6.12"
  defmacro named(x, want_struct) do
    quote location: :keep, bind_quoted: [x: x, want_struct: want_struct] do
      assert is_struct(x), Should.msg(x, "should be a struct")
      assert x.__struct__ == want_struct, Should.msg(x, "should be struct", want_struct)

      x
    end
  end

  @doc """
  Asserts when `x` is struct of `named` and has `key` then returns value of `key`

  ```
  struct = Should.Be.struct(x, named)

  # convert to map to test for key
  map = Map.from_struct(struct)
  val = Should.Be.Map.with_key(map, key)

  # return val of key
  val
  ```
  """
  @doc since: "0.6.12"
  defmacro with_key(x, named, key) do
    quote location: :keep, bind_quoted: [x: x, named: named, key: key] do
      struct = Should.Be.struct(x, named)

      # convert to map to test for key
      map = Map.from_struct(struct)
      val = Should.Be.Map.with_key(map, key)

      # return val of key
      val
    end
  end

  @doc """
  Asserts when `named/2` and contains all `Keyword` or `Map`

  ```
  Should.Be.struct(x, want_struct)

  assert Should.Be.List.check(kv_pairs) or Should.Be.Map.check(kv_pairs)

  map = Map.from_struct(x)

  Should.Contain.kv_pairs(map, kv_pairs)

  # return verified struct
  x
  ```
  """
  @doc since: "0.6.12"
  defmacro with_all_key_value(x, want_struct, kv_pairs) do
    quote location: :keep, bind_quoted: [x: x, want_struct: want_struct, kv_pairs: kv_pairs] do
      Should.Be.struct(x, want_struct)

      assert Should.Be.List.check(kv_pairs) or Should.Be.Map.check(kv_pairs)

      map = Map.from_struct(x)

      Should.Contain.kv_pairs(map, kv_pairs)

      # return verified struct
      x
    end
  end

  @doc """
  Asserts when `x` is `struct` of `named` and contains `[{key, val}]`

  ```
  kw_list = Keyword.new([{key, val}])
  Should.Be.Struct.with_all_key_value(x, named, kw_list)

  # return verified struct
  x
  ```
  """
  @doc since: "0.6.12"
  defmacro with_key_value(x, named, key, val) do
    quote location: :keep, bind_quoted: [x: x, named: named, key: key, val: val] do
      kw_list = Keyword.new([{key, val}])
      Should.Be.Struct.with_all_key_value(x, named, kw_list)

      # return verified struct
      x
    end
  end
end
