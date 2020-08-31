defmodule Roost do
  @moduledoc """
  Roost Public API
  """

  alias Roost.Server

  defdelegate active?, to: Server
  defdelegate all_stop, to: Server
  defdelegate available_modes, to: Server
  defdelegate cancel_delayed_cmd, to: Server
  def dance_with_me, do: mode(:dance_with_me)
  defdelegate last_timeout, to: Server
  def leaving, do: mode(:leaving)
  defdelegate restart(opts \\ []), to: Server
  defdelegate runtime_opts, to: Server
  defdelegate server_mode(mode_atom), to: Server
  defdelegate timeouts, to: Server
  defdelegate mode(mode, opts \\ []), to: Server
  defdelegate x_state(keys \\ []), to: Server

  @doc """
  Translate the internal state of the Roost server to an abstracted
  version suitable for external use.

  Returns a map
  """
  @doc since: "0.0.27"
  def status do
    alias Helen.Worker.Logic

    state = x_state()

    # translate the internal state to an abstracted version for external use
    %{mode: Logic.active_mode(state)}
  end
end
