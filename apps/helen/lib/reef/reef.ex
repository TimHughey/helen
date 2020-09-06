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
  defdelegate server_mode(opts), to: Captain, as: :server_mode

  @doc """
  Output the server options stored in the database.
  """
  @doc since: "0.0.27"
  def opts(server \\ [:captain]) when server in [:captain, :first_mate] do
    alias Reef.Captain.Opts, as: Captain
    alias Reef.FirstMate.Opts, as: FirstMate

    case server do
      :captain -> Captain.parsed()
      :first_mate -> FirstMate.parsed()
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
  def runtime_opts(server \\ [:captain])
      when server in [:captain, :first_mate] do
    case server do
      :captain -> Captain.runtime_opts()
      :first_mate -> FirstMate.runtime_opts()
    end
  end

  @doc """
  Translate the internal state of the Reef to an abstracted
  version suitable for external use.

  Returns a map
  """
  @doc since: "0.0.27"
  def status do
    %{captain: Captain.status()}
  end

  #   base = %{
  #     workers: %{
  #       captain: %{
  #         active: Captain.ready?(),
  #         mode: Captain.active_mode(),
  #         steps: [],
  #         devices: [
  #           %{
  #             name: "water_pump",
  #             online: MixTank.Pump.ready?(),
  #             active: MixTank.Pump.value(:simple)
  #           },
  #           %{
  #             name: "air_pump",
  #             online: MixTank.Air.ready?(),
  #             active: MixTank.Air.value(:simple)
  #           },
  #           %{
  #             name: "rodi_valve",
  #             online: MixTank.Rodi.ready?(),
  #             active: MixTank.Rodi.value(:simple)
  #           },
  #           %{
  #             name: "heater",
  #             online: MixTank.Temp.ready?(),
  #             active: MixTank.Temp.position(:simple)
  #           }
  #         ]
  #       },
  #       first_mate: %{
  #         mode: FirstMate.active_mode(),
  #         steps: []
  #       }
  #     }
  #   }
  #
  #   base
  #   # |> populate_worker_mode_status(captain_state, firstmate_state)
  # end

  # @doc """
  # Return a map of the Reef status
  # """
  # @doc since: "0.0.27"
  # def status_map do
  #   %{
  #     captain: %{
  #       available: Captain.ready?(),
  #       step: Captain.active_mode(),
  #       pump: %{
  #         active: MixTank.Pump.ready?(),
  #         position: MixTank.Pump.value(:simple)
  #       },
  #       air: %{
  #         active: MixTank.Air.ready?(),
  #         position: MixTank.Air.value(:simple)
  #       },
  #       rodi: %{
  #         active: MixTank.Rodi.ready?(),
  #         position: MixTank.Rodi.value(:simple)
  #       },
  #       heater: %{
  #         active: MixTank.Temp.ready?()
  #       }
  #     }
  #   }
  # end

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

  # @doc """
  # Set server test opts.
  #
  # Options:
  # `:captain` | `:first_mate`
  #
  # """

  # @doc since: "0.0.27"
  # def test_opts(server) when server in [:captain, :first_mate] do
  #   alias Reef.Captain
  #   alias Reef.FirstMate
  #
  #   case server do
  #     :captain ->
  #       Captain.Opts.test_opts()
  #       Captain.Server.restart()
  #
  #     :first_mate ->
  #       FirstMate.Opts.test_opts()
  #       FirstMate.Server.restart()
  #   end
  # end

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
      :displaytank_heat -> DisplayTank.Heat
    end
  end

  @doc delegate_to: {Captain, :mode, 2}
  defdelegate mode(mode, opts \\ []), to: Captain

  # defp populate_worker_mode_status(status_map, captain_state, first_mate_state) do
  #   worker_states = %{captain: captain_state, first_mate: first_mate_state}
  #
  #   worker_modes = %{
  #     captain: Captain.available_modes(),
  #     first_mate: FirstMate.available_modes()
  #   }
  #
  #   for {worker, modes} <- worker_modes, mode <- modes, reduce: status_map do
  #     status_map ->
  #       mode_status = %{
  #         step: mode,
  #         status: get_in(worker_states, [worker, mode, :status])
  #       }
  #
  #       steps =
  #         [get_in(status_map, [:workers, worker, :steps]), mode_status]
  #         |> List.flatten()
  #
  #       status_map |> put_in([:workers, worker, :steps], steps)
  #   end
  # end
end
