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
  Execute the steps required to perform the physical water change.
  """
  @doc since: "0.0.27"
  def change_water(opts), do: Captain.worker_mode(:change_water, opts)

  def default_opts do
    alias Reef.Opts.Prod

    opts(fn _x -> Prod.defaults() end)
    restart()
  end

  def test_opts do
    alias Reef.Opts.Test

    opts(fn _x -> Test.defaults() end)
    restart()
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

  defdelegate opts, to: Captain, as: :config_opts
  def opts(func) when is_function(func), do: Captain.config_update(func)

  defdelegate opts_dump, to: Captain, as: :config_dump

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

  @doc delegate_to: {Captain, :worker_mode, 2}
  defdelegate worker_mode(mode, opts \\ []), to: Captain

  defdelegate restart, to: Captain

  defdelegate rodi_off(opts \\ []), to: MixTank.Rodi, as: :off
  defdelegate rodi_on(opts \\ []), to: MixTank.Rodi, as: :on
  defdelegate rodi_toggle, to: MixTank.Rodi, as: :toggle

  @doc delegate_to: {Captain, :server_mode, 1}
  defdelegate mode(opts), to: Captain, as: :server_mode

  @doc """
  Output the Reef status based on the active reef mode.

  Outputs message to stdout, returns :ok.

  """
  @doc since: "0.0.27"
  def status, do: Status.msg() |> IO.puts()

  def standby_reason do
    case x_state(:standby_reason) do
      nil -> :none
      x -> x
    end
  end

  def temp_ok? do
    alias Reef.DisplayTank.Temp, as: DisplayTank
    alias Reef.MixTank.Temp, as: MixTank

    case {DisplayTank.temperature(), MixTank.temperature()} do
      {dt_temp, mt_temp} when is_number(dt_temp) and is_number(mt_temp) ->
        if abs(dt_temp - mt_temp) < 0.7, do: true, else: true

      _anything ->
        false
    end
  end

  def water_change_start do
    alias Reef.DisplayTank.Temp, as: DisplayTank
    alias Reef.MixTank.Temp, as: MixTank

    if temp_ok?() do
      [
        captain: all_stop(),
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
end
