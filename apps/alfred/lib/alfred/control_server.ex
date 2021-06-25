defmodule Alfred.Control.Server do
  defmodule State do
    defstruct timeout: %{last: nil, ms: 1000}, token: nil
  end

  require Logger
  use GenServer, shutdown: 2000

  alias __MODULE__, as: Mod

  def init(_args) do
    %State{} |> reply_ok()
  end

  def start_link(_opts) do
    Logger.debug(["starting ", inspect(Mod)])
    GenServer.start_link(Mod, [], name: Mod)
  end

  # defp noreply(s), do: {:noreply, s}
  # defp reply(s, val) when is_map(s), do: {:reply, val, s}
  # defp reply(val, s), do: {:reply, val, s}
  defp reply_ok(s), do: {:ok, s}
end
