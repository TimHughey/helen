defmodule Should.Be.Map do
  @moduledoc """
  Collection of macros for validating `Map` in `ExUnit.Case` tests
  """

  @doc """
  Asserts when `x` is `Map`

  ```
  assert is_map(x), Should.msg(x, "should be a map")
  ```
  """
  @doc since: "0.6.12"
  defmacro check(x) do
    quote location: :keep, bind_quoted: [x: x] do
      assert is_map(x), Should.msg(x, "should be a map")
    end
  end

  @doc """
  Asserts when `x` is a map and `Should.Contan.kv_pairs/3`

  ```
  assert Should.Be.map(x)

  Should.Contain.kv_pairs(x, kv_list)
  ```
  """
  @doc since: "0.6.12"
  defmacro with_all_key_value(x, kv_list) do
    quote location: :keep, bind_quoted: [x: x, kv_list: kv_list] do
      assert Should.Be.map(x)

      Should.Contain.kv_pairs(x, kv_list)
    end
  end

  @doc """
  Asserts `map` has `key`

  ```
  assert Should.Be.Map.check(map)
  assert is_map_key(map, key), Should.msg(map, "should have key", key)

  # return the value at the map key
  map[key]
  ```
  """
  @doc since: "0.6.12"
  defmacro with_key(map, key) do
    quote location: :keep, bind_quoted: [map: map, key: key] do
      assert Should.Be.Map.check(map)
      assert is_map_key(map, key), Should.msg(map, "should have key", key)

      # return the value at the map key
      map[key]
    end
  end

  @doc """
  Asserts `map` has list of `keys`

  ```
  assert Should.Be.NonEmpty.map(map)
  assert Should.Be.NonEmpty.list(keys)

  for key <- keys do
    assert is_map_key(map, key), Should.msg(map, "should have key", key)
  end

  # return a new map with only the verified keys
  Map.take(map, keys)
  ```
  """
  @doc since: "0.6.12"
  defmacro with_keys(map, keys) do
    quote location: :keep, bind_quoted: [map: map, keys: keys] do
      assert Should.Be.NonEmpty.map(map)
      assert Should.Be.NonEmpty.list(keys)

      for key <- keys do
        assert is_map_key(map, key), Should.msg(map, "should have key", key)
      end

      # return a new map with only the verified keys
      Map.take(map, keys)
    end
  end

  @doc """
  Refutes `map` size is `size`

  ```
  assert Should.Be.Map.check(map)
  refute map_size(map, size), Should.msg(map, "should be size", size)
  ```
  """
  @doc since: "0.6.12"
  defmacro with_size(map, size) do
    quote location: :keep, bind_quoted: [map: map, size: size] do
      assert Should.Be.Map.check(map)
      refute map_size(map) == size, Should.msg(map, "should be size", size)
    end
  end

  @doc """
  Refutes `map` has `key`

  ```
  assert Should.Be.Map.check(map)
  refute is_map_key(map, key), Should.msg(map, "should not have key", key)
  ```
  """
  @doc since: "0.6.12"
  defmacro without_key(map, key) do
    quote location: :keep, bind_quoted: [map: map, key: key] do
      assert Should.Be.Map.check(map)
      refute is_map_key(map, key), Should.msg(map, "should not have key", key)
    end
  end
end
