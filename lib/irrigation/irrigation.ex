defmodule Irrigation do
  @moduledoc """
    Irrigation Implementation for Wiss Landing
  """

  alias Irrigation.Server

  @doc delegate_to: {Server, :config_opts, 0}
  defdelegate opts, to: Server, as: :config_opts

  @doc delegate_to: {Server, :config_opts, 1}
  defdelegate opts(overrides), to: Server, as: :config_opts

  @doc delegate_to: {Server, :config_put, 1}
  defdelegate config_put(opts), to: Server

  @doc delegate_to: {Server, :config_merge, 1}
  defdelegate config_merge(opts), to: Server

  @doc delegate_to: {Server, :start_job, 1}
  defdelegate start_job(job_name, job_atom, tod_atom, duration_list),
    to: Server

  @doc delegate_to: {Server, :timeouts, 0}
  defdelegate timeouts, to: Server

  @doc """
  Execute a oneshot irrigation of the flower boxes

  Default [seconds: 45]

  Returns :ok

  ## Examples

      iex> Irrigation.front_porch_oneshot()
      :ok

      iex> Irrigation.front_porch_oneshot([seconds: 15])
      :ok

  """
  @doc since: "0.0.27"
  def front_porch_oneshot(opts \\ [seconds: 45]) do
    Server.start_job(:garden_oneshot, :garden, :oneshot, opts)
  end

  @doc """
  Execute a oneshot irrigation of the garden

  Default [minutes: 30]

  Returns :ok

  ## Examples

      iex> Irrigation.garden()
      :ok

      iex> Irrigation.garden([minutes: 30])
      :ok

  """
  @doc since: "0.0.27"

  def garden_oneshot(opts \\ [minutes: 30]) do
    Server.start_job(:garden_oneshot, :garden, :oneshot, opts)
  end

  @doc delegate_to: {Server, :restart, 0}
  defdelegate restart, to: Server

  @doc delegate_to: {Server, :state, 0}
  defdelegate state, to: Server
end
