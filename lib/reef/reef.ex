defmodule Reef do
  @moduledoc """
  Reef System Maintenance Command Line Interface
  """

  # def init(opts \\ []) when is_list(opts) do
  #   alias Thermostat.Server, as: T
  #   switches_all_off()
  #
  #   T.standby("mix tank")
  #   T.activate_profile("display tank", "75F")
  # end

  alias Reef.DisplayTank
  alias Reef.MixTank

  # def abort_all do
  #   MixTank.Temp.mode(:standby)
  #
  #   mods = [Reef.Salt.Aerate, Reef.Salt.Fill, Reef.Salt.KeepFresh]
  #
  #   for m <- mods do
  #     apply(m, :abort, [])
  #   end
  # end
  #
  # def aerate(opts \\ []), do: Reef.Salt.Aerate.kickstart(opts)
  # def aerate_abort(opts \\ []), do: Reef.Salt.Aerate.abort(opts)
  # def aerate_elapsed(opts \\ []), do: Reef.Salt.Aerate.elapsed_as_binary(opts)
  # def aerate_status(opts \\ []), do: Reef.Salt.Aerate.status(opts)
  # def aerate_state(opts \\ []), do: Reef.Salt.Aerate.state(opts)

  defdelegate air_off(opts \\ []), to: MixTank.Air, as: :off
  defdelegate air_on(opts \\ []), to: MixTank.Air, as: :on
  defdelegate air_toggle, to: MixTank.Air, as: :toggle

  def all_stop do
    # abort_all()
    #
    # Process.sleep(5000)

    mixtank_standby()
  end

  def clean(mode \\ :toggle, sw_name \\ "display tank ato")
      when is_atom(mode) and
             mode in [:engage, :disengage, :toggle, :help, :usage] and
             is_binary(sw_name) do
    {:ok, pos} = Switch.position(sw_name)

    # NOTE:
    #  display tank ato is wired normally on.  to turn off ATO set the
    #  switch to on.

    cond do
      mode == :toggle and pos == true ->
        Switch.toggle(sw_name)
        ["\nclean mode DISENGAGED\n"] |> IO.puts()
        :ok

      mode == :toggle and pos == false ->
        Switch.toggle(sw_name)
        ["\nclean mode ENGAGED\n"] |> IO.puts() |> IO.puts()
        :ok

      mode == :engage ->
        Switch.on(sw_name, lazy: false)
        ["\nclean mode forced to ENGAGED\n"] |> IO.puts()
        :ok

      mode == :disengage ->
        Switch.off(sw_name, lazy: false)
        ["\nclean mode forced to DISENGAGED\n"] |> IO.puts()
        :ok

      mode ->
        [
          "\n",
          "Reef.clean/1: \n",
          " :toggle    - toogle clean mode (default)\n",
          " :engage    - engage clean mode with lazy: false\n",
          " :disengage - disengage clean mode with lazy: false\n"
        ]
        |> IO.puts()

        :ok
    end
  end

  # def fill(opts \\ []), do: Reef.Salt.Fill.kickstart(opts)
  # def fill_abort(opts \\ []), do: Reef.Salt.Fill.abort(opts)
  # def fill_status(opts \\ []), do: Reef.Salt.Fill.status(opts)

  def heat_all_off do
    DisplayTank.Temp.mode(:standby)
    MixTank.Temp.mode(:standby)
  end

  # def keep_fresh(opts \\ []), do: Reef.Salt.KeepFresh.kickstart(opts)
  # def keep_fresh_abort(opts \\ []), do: Reef.Salt.KeepFresh.abort(opts)
  # def keep_fresh_status(opts \\ []), do: Reef.Salt.KeepFresh.status(opts)
  #
  # def match_display_tank do
  #   IO.puts(["not implemented!!"])
  # end

  # def mix(opts \\ []), do: Reef.Salt.Mix.kickstart(opts)
  # def mix_abort(opts \\ []), do: Reef.Salt.Mix.abort(opts)
  # def mix_status(opts \\ []), do: Reef.Salt.Mix.status(opts)

  def mixtank_mode(mode) when mode in [:active, :standby] do
    mods = [MixTank.Air, MixTank.Pump, MixTank.Rodi]

    for mod <- mods, into: [] do
      {mod, apply(mod, :mode, [mode])}
    end
  end

  def mixtank_online, do: mixtank_mode(:active)
  def mixtank_standby, do: mixtank_mode(:standby)

  defdelegate pump_off(opts \\ []), to: MixTank.Pump, as: :off
  defdelegate pump_on(opts \\ []), to: MixTank.Pump, as: :on
  defdelegate pump_toggle, to: MixTank.Pump, as: :toggle

  defdelegate rodi_off(opts \\ []), to: MixTank.Rodi, as: :off
  defdelegate rodi_on(opts \\ []), to: MixTank.Rodi, as: :on
  defdelegate rodi_toggle, to: MixTank.Rodi, as: :toggle

  def temp_ok? do
    dt_temp = Sensor.fahrenheit("display_tank", since_secs: 30)
    mt_temp = Sensor.fahrenheit("mixtank", since_secs: 30)

    diff = abs(dt_temp - mt_temp)

    if diff < 0.7, do: true, else: true
  end

  def water_change_complete do
    DisplayTank.Temp.mode(:active)
  end

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
