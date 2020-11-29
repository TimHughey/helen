defmodule Reef do
  @moduledoc """
  Reef System Maintenance Command Line Interface
  """

  alias Reef.Captain.Server, as: Captain
  alias Reef.FirstMate
  alias Reef.FirstMate.Server, as: FirstMate
  alias Reef.MixTank

  defdelegate ready?, to: Captain
  defdelegate air_off(opts \\ []), to: MixTank.Air, as: :off
  defdelegate air_on(opts \\ []), to: MixTank.Air, as: :on
  defdelegate air_toggle, to: MixTank.Air, as: :toggle

  @doc delegate_to: {Captain, :available_modes, 0}
  defdelegate available_modes, to: Captain, as: :available_modes

  @doc delegate_to: {Captain, :server_mode, 1}
  defdelegate server(mode), to: Captain, as: :server

  @doc """
  Output the server options stored in the database.
  """
  @doc since: "0.0.27"
  def opts(server \\ [:captain]) when server in [:captain, :first_mate] do
    alias Reef.Captain.Config, as: Captain
    alias Reef.FirstMate.Config, as: FirstMate

    case server do
      :captain -> Captain.config(:latest)
      :first_mate -> FirstMate.config(:latest)
    end
  end

  defdelegate pump_off(opts \\ []), to: MixTank.Pump, as: :off
  defdelegate pump_on(opts \\ []), to: MixTank.Pump, as: :on
  defdelegate pump_toggle, to: MixTank.Pump, as: :toggle

  defdelegate restart, to: Captain

  defdelegate rodi_off(opts \\ []), to: MixTank.Rodi, as: :off
  defdelegate rodi_on(opts \\ []), to: MixTank.Rodi, as: :on
  defdelegate rodi_toggle, to: MixTank.Rodi, as: :toggle

  @doc """
  Output the server runtime (active) options.
  """
  @doc since: "0.0.27"
  def runtime_opts(server \\ :captain) do
    case server do
      :captain -> Captain.runtime_opts()
      :first_mate -> FirstMate.runtime_opts()
      x -> %{unknown_worker: x}
    end
  end

  @doc """
  Translate the internal state of the Reef to an abstracted
  version suitable for external use.

  Returns a map
  """
  @doc since: "0.0.27"
  def status do
    %{workers: %{captain: Captain.status(), first_mate: FirstMate.status()}}
  end

  def temp_ok?(opts) do
    alias Reef.DisplayTank.Temp, as: DisplayTank
    alias Reef.MixTank.Temp, as: MixTank

    case {DisplayTank.temperature(), MixTank.temperature()} do
      {dt_temp, mt_temp} when is_number(dt_temp) and is_number(mt_temp) ->
        cond do
          opts[:skip_temp_check] == true -> true
          abs(dt_temp - mt_temp) >= 0.7 -> false
          true -> true
        end

      _anything ->
        false
    end
  end

  defdelegate x_which_children, to: Reef.Supervisor, as: :which_children

  @doc """
  Return the module of the reef worker
  """
  def worker(name) do
    alias Reef

    case name do
      :mixtank_air -> MixTank.Air
      :mixtank_pump -> MixTank.Pump
      :mixtank_rodi -> MixTank.Rodi
      :mixtank_heat -> Mixtank.Temp
      :displaytank_ato -> DisplayTank.Ato
      :displaytank_heat -> DisplayTank.Temp
    end
  end

  @doc delegate_to: {Captain, :mode, 2}
  defdelegate mode(mode, opts \\ []), to: Captain

  @doc false
  def worker_to_mod(worker) do
    if worker == "captain", do: Reef.Captain, else: Reef.FirstMate
  end
end
