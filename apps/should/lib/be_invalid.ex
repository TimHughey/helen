defmodule Should.Be.Invalid do
  @moduledoc """
  Collection of macros for invalid results
  """

  @doc """
  Asserts when tuple {:invaiid, binary}

  assert is_binary(x), Should.msg(x, "should be a binary")
  ```

  """
  @doc since: "0.6.12"
  defmacro tuple_with_binary(tuple, binaries) do
    quote location: :keep, bind_quoted: [tuple: tuple, binaries: binaries] do
      Should.Be.list(binaries)

      reason = Should.Be.Tuple.with_rc(tuple, :invalid)
      Should.Contain.binaries(reason, binaries)
    end
  end
end
