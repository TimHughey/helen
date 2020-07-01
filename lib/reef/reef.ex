defmodule Reef do
  @moduledoc """
  Reef System Maintenance Command Line Interface
  """

  alias Reef.Captain.Server, as: Captain
  alias Reef.Captain.Status, as: Status
  alias Reef.DisplayTank
  alias Reef.MixTank

  defdelegate active?, to: Captain
  defdelegate air_off(opts \\ []), to: MixTank.Air, as: :off
  defdelegate air_on(opts \\ []), to: MixTank.Air, as: :on
  defdelegate air_toggle, to: MixTank.Air, as: :toggle

  defdelegate all_stop, to: Captain

  defdelegate ato_state, to: DisplayTank.Ato, as: :state

  defdelegate clean, to: Captain

  def clean_status, do: state(:clean)

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
  def fill(opts \\ []), do: Captain.fill(opts)

  @doc """
  Reef mode Fill status.

  Outputs message to stdout, returns :ok.

  ## Examples

      iex> Reef.Captain.Server.fill_status()
      :ok

  """
  @doc since: "0.0.27"
  def fill_status, do: Status.msg(:fill) |> IO.puts()

  def heat_all_off do
    DisplayTank.Temp.mode(:standby)
    MixTank.Temp.mode(:standby)
  end

  @doc """
  A holding step of mixing a batch of reef replacement water.  This step
  is used between other steps to maintain the freshness of the new batch
  of water.
  """
  @doc since: "0.0.27"
  def keep_fresh(opts \\ []), do: Captain.keep_fresh(opts)

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
  The second step of mixing a batch of replacement water.  This step runs
  the necessary component while salt is added to the MixTank then executes
  an extended circulate and aerate before moving to keep fresh.
  """
  @doc since: "0.0.27"
  def mix_salt(opts \\ []), do: Captain.mix_salt(opts)

  @doc """
  Reef mode Mix Salt status.

  Outputs message to stdout, returns :ok.

  ## Examples

      iex> Reef.Captain.Server.mix_salt_status()
      :ok

  """
  @doc since: "0.0.27"
  def mix_salt_status, do: Status.msg(:salt_mix) |> IO.puts()

  # def match_display_tank do
  #   IO.puts(["not implemented!!"])
  # end

  @doc """
  Warm the MixTank to match the DisplayTank
  """
  @doc since: "0.0.27"
  def mixtank_match_display_tank do
    MixTank.Temp.restart()
  end

  def mixtank_mode(mode) when mode in [:active, :standby] do
    mods = [MixTank.Air, MixTank.Pump, MixTank.Rodi]

    for mod <- mods, into: [] do
      {mod, apply(mod, :mode, [mode])}
    end
  end

  def mixtank_online, do: mixtank_mode(:active)
  def mixtank_standby, do: mixtank_mode(:standby)

  def not_ready_reason do
    case state(:not_ready_reason) do
      nil -> :none
      x -> x
    end
  end

  defdelegate opts, to: Captain, as: :config_opts
  def opts(func) when is_function(func), do: Captain.config_update(func)

  defdelegate opts_dump, to: Captain, as: :config_dump

  defdelegate pump_off(opts \\ []), to: MixTank.Pump, as: :off
  defdelegate pump_on(opts \\ []), to: MixTank.Pump, as: :on
  defdelegate pump_toggle, to: MixTank.Pump, as: :toggle

  defdelegate restart, to: Captain

  defdelegate rodi_off(opts \\ []), to: MixTank.Rodi, as: :off
  defdelegate rodi_on(opts \\ []), to: MixTank.Rodi, as: :on
  defdelegate rodi_toggle, to: MixTank.Rodi, as: :toggle

  defdelegate state(opts \\ []), to: Captain

  def temp_ok? do
    dt_temp = Sensor.fahrenheit("display_tank", since_secs: 30)
    mt_temp = Sensor.fahrenheit("mixtank", since_secs: 30)

    diff = abs(dt_temp - mt_temp)

    if diff < 0.7, do: true, else: true
  end

  def water_change_complete do
    DisplayTank.Temp.mode(:active)
  end

  defdelegate which_children, to: Reef.Supervisor

  #
  # def water_change_begin(opts) when is_list(opts) do
  #   check_diff = Keyword.get(opts, :check_diff, true)
  #   allowed_diff = Keyword.get(opts, :allowed_diff, 0.8)
  #   interactive = Keyword.get(opts, :interactive, true)
  #
  #   mixtank_temp = Sensor.fahrenheit(name: "mixtank", since_secs: 30)
  #
  #   display_temp = Sensor.fahrenhei(name: "display_tank", since_secs: 30)
  #
  #   temp_diff = abs(mixtank_temp - display_temp)
  #
  #   if temp_diff > allowed_diff and check_diff do
  #     if interactive do
  #       IO.puts("--> WARNING <--")
  #
  #       IO.puts([
  #         " Mixtank and Display Tank variance greater than ",
  #         Float.to_string(allowed_diff)
  #       ])
  #
  #       IO.puts([
  #         " Display Tank: ",
  #         Float.round(display_temp, 1) |> Float.to_string(),
  #         "   Mixtank: ",
  #         Float.round(mixtank_temp, 1) |> Float.to_string()
  #       ])
  #     end
  #
  #     {:failed, {:temp_diff, temp_diff}}
  #   else
  #     rmp() |> halt()
  #     rma() |> halt()
  #     ato() |> halt()
  #
  #     status()
  #     {:ok}
  #   end
  # end
  #
  # def water_change_end do
  #   rmp() |> halt()
  #   rma() |> halt()
  #   ato() |> halt()
  #
  #   status()
  # end
  #
  # def xfer_swmt_to_wst,
  #   do: dc_activate_profile(rmp(), "mx to wst")
  #
  # def xfer_wst_to_sewer,
  #   do: dc_activate_profile(rmp(), "drain wst")
  #
end
