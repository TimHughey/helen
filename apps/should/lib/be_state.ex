defmodule Should.Be.State do
  @moduledoc """
  Macros for validating module names ending in `State`
  """

  @doc """
  Asserts when `x` is `State` and has `key`, returns `{x, key_val}`

  ```
  Should.Be.Struct.with_suffix(x, State)
  assert is_map_key(x, key), Should.msg(x, "should contain key", key)

  # return tuple of validated State and value of key
  {x, Map.get(x, key)}
  ```
  """
  @doc since: "0.2.26"

  defmacro with_key(x, key) do
    quote location: :keep, bind_quoted: [x: x, key: key] do
      Should.Be.Struct.with_suffix(x, State)
      assert is_map_key(x, key), Should.msg(x, "should contain key", key)

      # return tuple of validated State and value of key
      {x, Map.get(x, key)}
    end
  end
end
