defmodule RuthSim.Server do
  defmacro __using__(_opts) do
    quote location: :keep do
      alias unquote(__CALLER__.module), as: State

      def call(msg), do: RuthSim.Server.call(unquote(__CALLER__.module), msg)
      def cast(msg), do: RuthSim.Server.cast(unquote(__CALLER__.module), msg)

      def noreply(%State{} = s), do: {:noreply, s}
      def reply(res, %State{} = s), do: {:reply, res, s}
      def reply(%State{} = s, res), do: {:reply, res, s}
      def reply_ok(%State{} = s), do: {:ok, s}

      # misc logging
      def log_unmatched(msg, from, %State{} = s) do
        RuthSim.Server.log_unmatched(msg, from, s) |> Logger.warn()
        reply(:unmatched_call, s)
      end
    end
  end

  def call(mod, msg) do
    if Process.whereis(mod) do
      GenServer.call(mod, msg)
    else
      {:no_server, mod}
    end
  end

  def cast(mod, msg) do
    if Process.whereis(mod) do
      GenServer.cast(mod, msg)
    else
      {:no_server, mod}
    end
  end

  def log_unmatched(msg, from, %_{} = s) do
    """

    from:
    #{inspect(from)}

    message:
    #{inspect(msg, pretty: true)}

    state:
    #{inspect(s, pretty: true)}

    """
  end
end
