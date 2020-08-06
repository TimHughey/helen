defmodule Roost do
  @moduledoc """
  Roost Public API
  """

  alias Roost.Server

  defdelegate active?, to: Server
  defdelegate all_stop, to: Server
  defdelegate available_modes, to: Server
  defdelegate cancel_delayed_cmd, to: Server
  def dance_with_me, do: worker_mode(:dance_with_me)
  defdelegate last_timeout, to: Server
  def leaving, do: worker_mode(:leaving)
  defdelegate restart(opts \\ []), to: Server
  defdelegate runtime_opts, to: Server
  defdelegate server_mode(mode_atom), to: Server
  defdelegate timeouts, to: Server
  defdelegate worker_mode(mode, opts \\ []), to: Server
  defdelegate x_state(keys \\ []), to: Server

  def status do
    %{worker_mode: mode} = x_state()

    # translate the internal state to an abstracted version for external use
    %{mode: mode}
  end
end
