defmodule Should.Contain do
  @moduledoc """
  Collection of macros for validating contents in `ExUnit.Case` tests
  """

  @doc """
  Verifies a binary contains a list of binaries

  ```
  Should.Be.binary(check)

  bin_list = List.wrap(bin_list)

  for x <- bin_list do
    Should.Be.binary(x)
    assert String.contains?(check, x), Should.msg(check, "should contain", x)
  end

  # return verified binary
  check
  ```
  """
  @doc since: "0.6.12"
  defmacro binaries(check, bin_list) do
    quote bind_quoted: [check: check, bin_list: bin_list] do
      Should.Be.binary(check)

      bin_list = List.wrap(bin_list)

      for x <- bin_list do
        Should.Be.binary(x)
        assert String.contains?(check, x), Should.msg(check, "should contain", x)
      end

      # return verified binary
      check
    end
  end

  @doc """
  Asserts when `x` contains `key`, returns `{x, value}`

  ```
  # ensure x is an enumberable
  x = if(is_struct(x), do: Map.from_struct(x), else: x)

  value = x[want_key] || :want_key_not_found

  refute value == :want_key_not_found, Should.msg(x, "should contain key", want_key)

  # return tuple
  case return do
    :value -> value
    :tuple -> {x, value}
  end
  ```

  """
  @doc since: "0.6.34"
  defmacro key(x, want_key, return \\ :value) do
    quote bind_quoted: [x: x, want_key: want_key, return: return] do
      # ensure x is an enumberable
      x = if(is_struct(x), do: Map.from_struct(x), else: x)

      value = x[want_key] || :want_key_not_found

      refute value == :want_key_not_found, Should.msg(x, "should contain key", want_key)

      # return tuple
      case return do
        :value -> value
        :tuple -> {x, value}
      end
    end
  end

  @doc """
  Asserts when `Enum` contains `keys`

  ```
  # ensure x is an enumberable
  x = if(is_struct(x), do: Map.from_struct(x), else: x)

  for want_key <- want_keys do
    found? = Enum.any?(x, fn {k, _v} -> k == want_key end)
    assert found?, Should.msg(x, "should contain key", want_key)
  end

  # return verified enumerable
  x
  ```

  """
  @doc since: "0.6.19"
  defmacro keys(x, want_keys) do
    quote bind_quoted: [x: x, want_keys: want_keys] do
      # ensure x is an enumberable
      x = if(is_struct(x), do: Map.from_struct(x), else: x)

      for want_key <- want_keys do
        found? = Enum.any?(x, fn {k, _v} -> k == want_key end)
        assert found?, Should.msg(x, "should contain key", want_key)
      end

      # return verified enumerable
      x
    end
  end

  @doc """
  Asserts when `Enum` contains key/value pairs

  ```
  # ensure x is an enumerable
  x = if(is_struct(x), do: Map.from_struct(x), else: x)

  for kv <- kv_pairs do
    found? = Enum.any?(x, &(&1 == kv))
    assert found?, Should.msg(x, "should contain", kv)
  end

  # return verified enumerable
  x
  ```

  """
  @doc since: "0.6.12"
  defmacro kv_pairs(x, kv_pairs) do
    quote bind_quoted: [x: x, kv_pairs: kv_pairs] do
      Should.Be.list(kv_pairs)

      # ensure x is an enumberable
      x = if(is_struct(x), do: Map.from_struct(x), else: x)

      for kv <- kv_pairs do
        found? = Enum.any?(x, &(&1 == kv))
        assert found?, Should.msg(x, "should contain", kv)
      end

      # return verified enumerable
      x
    end
  end

  @doc """
  Asserts when `x` contains `keys` of `types`

  ```
  Should.Be.List.of_tuples(want_types, 2)
  assert can_be_enumerated, Should.msg(x, "should be keyword list, map or struct")

  check = if(is_struct(x), do: Map.to_struct(x), else: x)

  for {key, type} <- want_types, {^key, check_type} <- check do
    Shuold.Be.type(check_type, type, key, check)
  end

  # returns validated x
  x
  ```
  """
  @doc since: "0.6.34"
  defmacro types(x, want_types) do
    quote bind_quoted: [x: x, want_types: want_types] do
      Should.Be.List.of_tuples_with_size(want_types, 2)

      can_be_enumerated? = Should.Contain.can_be_enumerated?(x)
      assert can_be_enumerated?, Should.msg(x, "should be keyword list, map or struct")

      check = if(is_struct(x), do: Map.from_struct(x), else: x)

      for {key, type} <- want_types, {^key, check_type} <- check do
        Should.Be.type(check_type, type, key)
      end

      # returns validated x
      x
    end
  end

  @doc """
  Asserts when `Enum` (or `struct`) contains `what`

  ```
  assert is_list(x) or is_struct(x) or is_map(x), Should.msg(x, "should be enumerable")

  check = if(is_struct(x), do: Map.to_struct(x), else: x)

  assert Enum.find(check, false, fn
           {v, _} -> v == what
           {_k, v} -> v == what
           v -> v == what
         end),
         msg(check, "should contain value", what)
  ```

  """
  @doc since: "0.6.23"
  defmacro value(x, what) do
    quote bind_quoted: [x: x, what: what] do
      assert is_list(x) or is_struct(x) or is_map(x), Should.msg(x, "should be enumerable")

      check = if(is_struct(x), do: Map.from_struct(x), else: x)

      assert Enum.find(check, false, fn
               {^what, _} -> true
               {_k, ^what} -> true
               ^what -> true
               _ -> false
             end),
             Should.msg(check, "should contain value", what)
    end
  end

  @doc false
  def can_be_enumerated?(x) do
    case x do
      x when is_list(x) -> Keyword.keyword?(x)
      x when is_struct(x) -> true
      x when is_map(x) -> true
      _x -> false
    end
  end
end
