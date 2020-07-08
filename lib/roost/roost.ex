defmodule Roost do
  @moduledoc """
  Roost Public API
  """

  alias Roost.Server

  defdelegate active?, to: Server
  defdelegate all_stop, to: Server
  defdelegate available_modes, to: Server
  defdelegate cancel_delayed_cmd, to: Server
  defdelegate dance_with_me, to: Server
  defdelegate last_timeout, to: Server
  defdelegate leaving, to: Server
  defdelegate restart(opts \\ []), to: Server
  defdelegate runtime_opts, to: Server
  defdelegate server_mode(mode_atom), to: Server
  defdelegate timeouts, to: Server
  defdelegate worker_mode(mode, opts \\ []), to: Server
  defdelegate x_state(keys \\ []), to: Server
end
