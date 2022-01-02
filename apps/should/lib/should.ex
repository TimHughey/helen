defmodule Should do
  defmacro __using__(_use_opts) do
    quote do
      require Should
      import Should, only: [pretty_puts: 1]
    end
  end

  @doc """
  Assert a GenServer has started (using `server_name`)

  """
  @doc since: "0.7.1"
  defmacro assert_started(server_name, opts) do
    quote bind_quoted: [server_name: server_name, opts: opts] do
      sleep = opts[:sleep] || 10
      reductions = opts[:attempts] || 1

      assert Enum.reduce(1..reductions, :check, fn
               _x, :check -> GenServer.whereis(server_name)
               _x, pid when is_pid(pid) -> Process.alive?(pid)
               _x, false -> Process.sleep(sleep) && :check
               _x, true -> true
             end)

      assert GenServer.whereis(server_name)
    end
  end

  @doc """
  Output pretty `x` and passthrough `x`

  ```
  tap(x, -> IO.puts(["\\n", inspect(x, pretty: true)])
  ```
  """
  @doc since: "0.1.0"
  defmacro pretty_puts(x) do
    quote bind_quoted: [x: x] do
      tap(x, fn x -> IO.puts(["\n", inspect(x, pretty: true)]) end)
    end
  end
end
