defmodule Roost do
  @moduledoc """
  Roost Public API
  """

  use Helen.Worker.Config

  alias Roost.Server

  defdelegate ready?, to: Server
  defdelegate available_modes, to: Server
  defdelegate cancel_delayed_cmd, to: Server
  defdelegate last_timeout, to: Server
  defdelegate restart(opts \\ []), to: Server
  defdelegate runtime_opts, to: Server

  def status do
    %{workers: %{roost: Server.status()}}
  end

  defdelegate server(mode), to: Server
  defdelegate timeouts, to: Server
  defdelegate mode(mode, opts \\ []), to: Server
end
