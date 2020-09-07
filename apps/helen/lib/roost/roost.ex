defmodule Roost do
  @moduledoc """
  Roost Public API
  """

  alias Roost.Server

  defdelegate ready?, to: Server
  defdelegate available_modes, to: Server
  defdelegate cancel_delayed_cmd, to: Server
  defdelegate last_timeout, to: Server
  defdelegate restart(opts \\ []), to: Server
  defdelegate runtime_opts, to: Server
  defdelegate server(mode), to: Server
  defdelegate timeouts, to: Server
  defdelegate mode(mode, opts \\ []), to: Server

  @doc """
  Translate the internal state of the Roost server to an abstracted
  version suitable for external use.

  Returns a map
  """
  @doc since: "0.0.27"
  def status do
    # translate the internal state to an abstracted version for external use
    %{mode: Server.active_mode()}
  end
end
