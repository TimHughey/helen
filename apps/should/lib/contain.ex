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
    quote location: :keep, bind_quoted: [check: check, bin_list: bin_list] do
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
    quote location: :keep, bind_quoted: [x: x, want_keys: want_keys] do
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
    quote location: :keep, bind_quoted: [x: x, kv_pairs: kv_pairs] do
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
end
