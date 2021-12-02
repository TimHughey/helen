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
  # ensure x is an enumberable
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
end
