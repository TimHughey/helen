defmodule Should.Be.Schema do
  @moduledoc """
  Collection of macros for schema assertions
  """

  @doc """
  Asserts when `x` is a schema of `want`

  ```
  meta = Should.Be.Struct.with_key(x, want, :__meta__)

  assert meta.schema == want, Should.msg(x, "should be schema", want)

  x
  ```
  """
  @doc since: "0.2.6"
  defmacro named(x, want) do
    quote location: :keep, bind_quoted: [x: x, want: want] do
      meta = Should.Be.Struct.with_key(x, want, :__meta__)

      assert meta.schema == want, Should.msg(x, "should be schema", want)

      x
    end
  end

  @doc """
  Asserts when `Should.Be.Schema.named/2` and contains all `Keyword` or `Map`

  ```
  Should.Be.Schema.named(x, want_schema)

  assert Should.Be.List.check(kv_pairs) or Should.Be.Map.check(kv_pairs)

  as_map = Map.from_struct(x)

  Should.Contain.kv_pairs(map, kv_pairs)
  ```

  """
  @doc since: "0.6.12"
  defmacro with_all_key_value(x, want_schema, kv_pairs) do
    quote location: :keep, bind_quoted: [x: x, want_schema: want_schema, kv_pairs: kv_pairs] do
      Should.Be.Schema.named(x, want_schema)

      assert Should.Be.List.check(kv_pairs) or Should.Be.Map.check(kv_pairs)

      Should.Contain.kv_pairs(x, kv_pairs)
    end
  end
end
