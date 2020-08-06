defmodule Reef do
  @moduledoc """
  Reef System Maintenance Command Line Interface
  """

  alias Reef.Captain.Server, as: Captain
  alias Reef.Captain.Status, as: Status
  alias Reef.FirstMate
  alias Reef.FirstMate.Server, as: FirstMate
  alias Reef.MixTank

  defdelegate active?, to: Captain
  defdelegate air_off(opts \\ []), to: MixTank.Air, as: :off
  defdelegate air_on(opts \\ []), to: MixTank.Air, as: :on
  defdelegate air_toggle, to: MixTank.Air, as: :toggle

  defdelegate all_stop, to: Captain

  @doc delegate_to: {Captain, :available_modes, 0}
  defdelegate available_worker_modes, to: Captain, as: :available_modes

  @doc """
  Engage clean mode by turning off the DisplayTank auto-top-off.
  """
  @doc since: "0.0.27"
  def clean(opts \\ []) do
    FirstMate.worker_mode(:clean, opts)
  end

  @doc """
  Output the clean mode status
  """
  @doc since: "0.0.27"
  def clean_status do
    firstmate_status()
  end

  @doc """
  The first step of mixing a batch of reef replacement water.  This step
  fills the MixTank with RODI.
  """
  @doc since: "0.0.27"
  def fill(opts \\ []) do
    Captain.worker_mode(:fill, opts)
  end

  @doc """
  Reef mode Fill status.

  Outputs message to stdout, returns :ok.

  ## Examples

      iex> Reef.Captain.Server.fill_status()
      :ok

  """
  @doc since: "0.0.27"
  def fill_status, do: Status.msg(:fill) |> IO.puts()

  @doc delegate_to: {FirstMate, :all_stop, 0}
  defdelegate firstmate_all_stop, to: FirstMate, as: :all_stop

  @doc delegate_to: {FirstMate, :config_opts, 1}
  defdelegate firstmate_opts(opts \\ []), to: FirstMate, as: :config_opts

  @doc """
  Output the status of FirstMate
  """
  @doc since: "0.0.27"
  def firstmate_status do
    alias Reef.FirstMate

    firstmate_x_state() |> FirstMate.Status.msg() |> IO.puts()
  end

  @doc delegate_to: {FirstMate, :x_state, 1}
  defdelegate firstmate_x_state(opts \\ []), to: FirstMate, as: :x_state

  def heat_all_off do
    alias Reef.DisplayTank.Temp, as: DisplayTank
    alias Reef.MixTank.Temp, as: MixTank

    DisplayTank.mode(:standby)
    MixTank.mode(:standby)
  end

  @doc """
  A holding step of mixing a batch of reef replacement water.  This step
  is used between other steps to maintain the freshness of the new batch
  of water.
  """
  @doc since: "0.0.27"
  def keep_fresh(opts \\ []), do: Captain.worker_mode(:keep_fresh, opts)

  @doc """
  Reef mode Keep Fresh status.

  Outputs message to stdout, returns :ok.

  ## Examples

      iex> Reef.Captain.Server.keep_fresh_status()
      :ok

  """
  @doc since: "0.0.27"
  def keep_fresh_status, do: Status.msg(:keep_fresh) |> IO.puts()

  @doc """
  Runs the necessary components to mix salt into the MixTank.

  Returns `:ok`, `{:not_configured, opts}` or `{:invalid_duration_opts}`

  ## Examples

      iex> Reef.mix_salt()
      :ok

  ### Example Options
    `start_delay: "PT5M30S"` delay the start of this command by 1 min 30 secs

  """
  @doc since: "0.0.27"
  def mix_salt(opts \\ []), do: Captain.worker_mode(:mix_salt, opts)

  @doc """
  Reef mode Mix Salt status.

  Outputs message to stdout, returns :ok.

  ## Examples

      iex> Reef.Captain.Server.mix_salt_status()
      :ok

  """
  @doc since: "0.0.27"
  def mix_salt_status, do: Status.msg(:salt_mix) |> IO.puts()

  @doc delegate_to: {Captain, :server_mode, 1}
  defdelegate mode(opts), to: Captain, as: :server_mode

  @doc """
  Output the server options stored in the database.
  """
  @doc since: "0.0.27"
  def opts(server \\ [:captain]) when server in [:captain, :first_mate] do
    case server do
      :captain -> Captain.config_opts()
      :first_mate -> FirstMate.config_opts()
    end
  end

  @doc """
  Prepare the MixTank for transfer to Water Stabilization Tank

  Returns :ok or an error tuple
  """
  @doc since: "0.0.27"
  def prep_for_change(opts \\ []),
    do: Captain.worker_mode(:prep_for_change, opts)

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
  Output the Reef status based on the active reef mode.

  Outputs message to stdout, returns :ok.

  """
  @doc since: "0.0.27"
  def status, do: Status.msg() |> IO.puts()

  @doc """
  Return a map of the Reef status
  """
  @doc since: "0.0.27"
  def status_map do
    %{worker_mode: captain_worker_mode} = Captain.x_state()

    %{
      captain: %{
        available: Captain.active?(),
        step: captain_worker_mode,
        steps: %{
          fill: %{active: false, completed: false},
          keep_fresh: %{active: false, completed: false},
          add_salt: %{active: false, completed: false},
          match_conditions: %{active: false, completed: false},
          dump_water: %{active: false, completed: false},
          load_water: %{active: false, completed: false},
          final_check: %{active: false, completed: false}
        },
        pump: %{
          active: MixTank.Pump.active?(),
          position: MixTank.Pump.value(:simple)
        },
        air: %{
          active: MixTank.Air.active?(),
          position: MixTank.Air.value(:simple)
        },
        rodi: %{
          active: MixTank.Rodi.active?(),
          position: MixTank.Rodi.value(:simple)
        },
        heater: %{
          active: MixTank.Temp.active?()
        }
      }
    }
  end

  def standby_reason do
    case x_state(:standby_reason) do
      nil -> :none
      x -> x
    end
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

  @doc """
  Set server test opts.

  Options:
  `:captain` | `:first_mate`

  """
  @doc since: "0.0.27"
  def test_opts(server) when server in [:captain, :first_mate] do
    alias Reef.Captain
    alias Reef.FirstMate

    case server do
      :captain ->
        Captain.Opts.test_opts()
        Captain.Server.restart()

      :first_mate ->
        FirstMate.Opts.test_opts()
        FirstMate.Server.restart()
    end
  end

  @doc """
  Execute the steps required to perform the physical water change.
  """
  @doc since: "0.0.27"
  def water_change(opts \\ [skip_temp_check: false]) do
    alias Reef.Captain.Server, as: Captain
    alias Reef.DisplayTank.Temp, as: DisplayTank
    alias Reef.MixTank.Temp, as: MixTank

    if temp_ok?(opts) do
      [
        captain: Captain.worker_mode(:water_change, []),
        first_mate: FirstMate.worker_mode(:water_change_start, []),
        display_tank: DisplayTank.mode(:standby)
      ]
    else
      [
        temperature_mismatch: [
          display_tank: DisplayTank.temperature(),
          mixtank: MixTank.temperature()
        ]
      ]
    end
  end

  def water_change_finish do
    alias Reef.DisplayTank.Temp, as: DisplayTank
    alias Reef.MixTank.Temp, as: MixTank

    [
      captain: all_stop(),
      first_mate: FirstMate.worker_mode(:water_change_finish, []),
      display_tank: DisplayTank.mode(:active),
      mixtank: MixTank.mode(:standby)
    ]
  end

  defdelegate x_which_children, to: Reef.Supervisor, as: :which_children
  defdelegate x_state(opts \\ []), to: Captain

  @doc delegate_to: {Captain, :worker_mode, 2}
  defdelegate worker_mode(mode, opts \\ []), to: Captain
end
