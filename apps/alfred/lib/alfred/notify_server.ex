defmodule Alfred.NotifyServer do
  use GenServer, shutdown: 2000

  require Logger

  alias Alfred.NotifyServer, as: Mod
  alias Alfred.NotifyServerState, as: State

  def init(_args) do
    %State{} |> reply_ok()
  end

  def start_link(_opts) do
    Logger.info(["starting ", inspect(Mod)])
    GenServer.start_link(__MODULE__, [], name: Mod)
  end

  # defp noreply(s), do: {:noreply, s}
  # defp reply(s, val) when is_map(s), do: {:reply, val, s}
  # defp reply(val, s), do: {:reply, val, s}
  defp reply_ok(s), do: {:ok, s}
end
