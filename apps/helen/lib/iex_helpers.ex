defmodule Helen.IExHelpers do
  @moduledoc false

  def server_state(mod), do: :sys.get_state(mod)
  def server_status(mod), do: :sys.get_status(mod)

  def server_pid(mod) do
    {:status, pid, _} = :sys.get_status(mod)
    pid
  end

  def observer do
    :observer.start()
    Node.connect(:"prod@helen.live.wisslanding.com")
  end
end

## defmodule end
