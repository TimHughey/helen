defmodule Should.Be.Map do
  @moduledoc """
  Collection of macros for validating `Map` in `ExUnit.Case` tests
  """

  # @doc """
  # Asserts when `x` is `Map`
  #
  # ```
  # assert is_map(x), Should.msg(x, "should be a map")
  # ```
  # """
  # @doc since: "0.6.12"
  # defmacro check(x) do
  #   quote location: :keep, bind_quoted: [x: x] do
  #     assert is_map(x), Should.msg(x, "should be a map")
  #   end
  # end

  @doc """
  Asserts when `x` is empty `Map`

  ```
  Should.Be.map(x)
  assert map_size(x) == 0, Should.msg(x, "should be size zero")
  ```
  """
  @doc since: "0.6.26"
  defmacro empty(x) do
    quote location: :keep, bind_quoted: [x: x] do
      Should.Be.map(x)
      assert map_size(x) == 0, Should.msg(x, "should be empty")
    end
  end

  @doc """
  Asserts when `x` is a `map` and the `keys` are of `types`, returns validated `map`

  ```
  Should.Be.NonEmpty.list(types)

  assert Keyword.keyword?(types), Should.msg(types, "types should be a Keyword list")

  Should.Be.Map.with_keys(x, Keyword.keys(types))

  for {key, type} <- types do
    val = Map.get(x, key)
    Should.Be.type(val, type, val, "key #{inspect(key)}")
  end

  # return x
  x
  ```
  """
  @doc since: "0.2.32"
  defmacro of_key_types(x, types) do
    quote location: :keep, bind_quoted: [x: x, types: types] do
      Should.Be.NonEmpty.list(types)

      assert Keyword.keyword?(types), Should.msg(types, "types should be a Keyword list")

      Should.Be.Map.with_keys(x, Keyword.keys(types))

      for {key, type} <- types do
        val = Map.get(x, key)
        Should.Be.type(val, type, val, "key #{inspect(key)}")
      end

      # return x
      x
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
  assert Should.Be.map(map)
  assert is_map_key(map, key), Should.msg(map, "should have key", key)

  # return the value at the map key
  map[key]
  ```
  """
  @doc since: "0.6.12"
  defmacro with_key(map, key) do
    quote location: :keep, bind_quoted: [map: map, key: key] do
      assert Should.Be.map(map)
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
  Refutes `map` size is `size`, returns map

  ```
  assert Should.Be.map(map)
  assert map_size(map) == size, Should.msg(map, "should be size", size)

  # return map
  map
  ```
  """
  @doc since: "0.6.12"
  defmacro with_size(map, size) do
    quote location: :keep, bind_quoted: [map: map, size: size] do
      assert Should.Be.map(map)
      assert map_size(map) == size, Should.msg(map, "should be size", size)

      # return map
      map
    end
  end

  @doc """
  Refutes `map` has `key`, returns map

  ```
  assert Should.Be.map(map)
  refute is_map_key(map, key), Should.msg(map, "should not have key", key)

  # return map
  map
  ```
  """
  @doc since: "0.6.12"
  defmacro without_key(map, key) do
    quote location: :keep, bind_quoted: [map: map, key: key] do
      assert Should.Be.map(map)
      refute is_map_key(map, key), Should.msg(map, "should not have key", key)

      # return map
      map
    end
  end
end
