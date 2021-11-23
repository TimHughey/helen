defmodule Should.Be.NonEmpty do
  @moduledoc """
  Collection of macros for validating collectables are not empty
  """

  @doc """
  Asserts when is non-empty `List` then returns verified list

  ```
  list = Should.Be.list(x)
  refute list == [], Should.msg(list, "should be non-empty list")

  list
  ```

  """
  @doc since: "0.6.12"
  defmacro list(x) do
    quote location: :keep, bind_quoted: [x: x] do
      list = Should.Be.list(x)
      refute list == [], Should.msg(list, "should be non-empty list")

      list
    end
  end

  @doc """
  Asserts when is non-empty `Map` then returns verified map

  ```
  map = Should.Be.map(x)
  refute map_size(map) == 0, Should.msg(map, "should be non-empty map")

  # return verified map
  map
  ```

  """
  @doc since: "0.6.12"
  defmacro map(x) do
    quote location: :keep, bind_quoted: [x: x] do
      map = Should.Be.map(x)
      refute map_size(map) == 0, Should.msg(map, "should be non-empty map")

      # return verified map
      map
    end
  end
end
