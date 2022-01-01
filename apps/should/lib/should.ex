defmodule Should do
  defmacro __using__(_opts) do
    quote do
      import Should, only: [pretty_puts: 1]
    end
  end

  @doc """
  Output pretty `x` and passthrough `x`

  ```
  tap(x, -> IO.puts(["\\n", inspect(x, pretty: true)])
  ```
  """
  defmacro pretty_puts(x) do
    quote bind_quoted: [x: x] do
      tap(x, fn x -> IO.puts(["\n", inspect(x, pretty: true)]) end)
    end
  end
end
