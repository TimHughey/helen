defmodule HelenTestHelpers do
  @moduledoc false

  defmacro pretty(x) do
    quote do
      "\n#{inspect(unquote(x), pretty: true)}"
    end
  end

  defmacro pretty(msg, x) do
    quote bind_quoted: [msg: msg, x: x] do
      msg <> "\n#{inspect(x, pretty: true)}"
    end
  end
end
