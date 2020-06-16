defmodule Reef do
  @moduledoc """
  Reef System Maintenance Command Line Interface
  """

  @compile {:no_warn_undefined, Thermostat.Server}
  @compile {:no_warn_undefined, Sensor}

  # import IO.ANSI

  def init(opts \\ []) when is_list(opts) do
    alias Thermostat.Server, as: T
    switches_all_off()

    T.standby("mix tank")
    T.activate_profile("display tank", "75F")
  end

  def abort_all do
    alias Thermostat.Server, as: T

    T.standby("mix tank")

    mods = [Reef.Salt.Aerate, Reef.Salt.Fill, Reef.Salt.KeepFresh]

    for m <- mods do
      apply(m, :abort, [])
    end
  end

  def aerate(opts \\ []), do: Reef.Salt.Aerate.kickstart(opts)
  def aerate_abort(opts \\ []), do: Reef.Salt.Aerate.abort(opts)
  def aerate_elapsed(opts \\ []), do: Reef.Salt.Aerate.elapsed_as_binary(opts)
  def aerate_status(opts \\ []), do: Reef.Salt.Aerate.status(opts)
  def aerate_state(opts \\ []), do: Reef.Salt.Aerate.state(opts)

  def clean(mode \\ :toggle, sw_name \\ "display tank ato")
      when is_atom(mode) and mode in [:engage, :disengage, :toggle, :help, :usage] and
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

  def fill(opts \\ []), do: Reef.Salt.Fill.kickstart(opts)
  def fill_abort(opts \\ []), do: Reef.Salt.Fill.abort(opts)
  def fill_status(opts \\ []), do: Reef.Salt.Fill.status(opts)

  def heat_all_off do
    alias Thermostat.Server, as: T

    heaters = ["mix tank", "display tank"]

    for h <- heaters do
      T.standby(h)
    end
  end

  def keep_fresh(opts \\ []), do: Reef.Salt.KeepFresh.kickstart(opts)
  def keep_fresh_abort(opts \\ []), do: Reef.Salt.KeepFresh.abort(opts)
  def keep_fresh_status(opts \\ []), do: Reef.Salt.KeepFresh.status(opts)

  def match_display_tank do
    alias Thermostat.Server, as: T

    [
      thermostat: T.activate_profile("mix tank", "prep for change"),
      ato: Switch.off("display tank ato"),
      keep_fresh: keep_fresh()
    ]
  end

  def mix(opts \\ []), do: Reef.Salt.Mix.kickstart(opts)
  def mix_abort(opts \\ []), do: Reef.Salt.Mix.abort(opts)
  def mix_status(opts \\ []), do: Reef.Salt.Mix.status(opts)

  def pump_toggle do
    Switch.toggle("mix pump")
  end

  def switches_all_off(opts \\ ["mixtank"]) when is_list(opts) do
    sw_names = for x <- opts, do: Switch.names_begin_with(x)

    for s <- List.flatten(sw_names), do: Switch.off(s)
  end

  def t_activate({n, p}) when is_binary(n) and is_binary(p) do
    alias Thermostat.Server, as: T

    T.activate_profile(n, p)
  end

  def t_standby(n) when is_binary(n) do
    alias Thermostat.Server, as: T

    T.standby(n)
  end

  def temp_ok? do
    dt_temp = Sensor.fahrenheit("display_tank", since_secs: 30)
    mt_temp = Sensor.fahrenheit("mixtank", since_secs: 30)

    diff = abs(dt_temp - mt_temp)

    if diff < 0.7, do: true, else: true
  end

  def water_change_complete do
    alias Thermostat.Server, as: T

    T.activate_profile("display tank", "75F")
  end

  ##
  ## Testing Purposes
  ##

  def test_aerate, do: test_opts_aerate() |> Reef.aerate()
  def test_fill, do: test_opts_fill() |> Reef.fill()
  def test_keep_fresh, do: test_opts_keep_fresh() |> Reef.keep_fresh()
  def test_mix, do: test_opts_mix() |> Reef.mix()

  def test_opts_aerate do
    [
      switch_air: "mixtank_air",
      switch_pump: "mixtank_pump",
      aerate_time: [seconds: 10],
      air_on: [seconds: 1],
      air_off: [seconds: 1],
      pump_on: [seconds: 1],
      pump_off: [seconds: 1]
    ]
  end

  def test_opts_fill do
    [
      fill_time: [seconds: 1],
      topoff_time: [seconds: 1],
      valve_open: [seconds: 1],
      valve_closed: [seconds: 1]
    ]
  end

  def test_opts_keep_fresh do
    [
      switch_air: "mixtank_air",
      switch_pump: "mixtank_pump",
      keep_fresh_time: [seconds: 10],
      air_on: [seconds: 1],
      air_off: [seconds: 1],
      pump_on: [seconds: 1],
      pump_off: [seconds: 1]
    ]
  end

  def test_opts_mix do
    [
      switch_air: "mixtank_air",
      switch_pump: "mixtank_pump",
      mix_time: [seconds: 10],
      air_on: [seconds: 1],
      air_off: [seconds: 1],
      pump_on: [seconds: 1],
      pump_off: [seconds: 1]
    ]
  end

  def future_example do
    [
      group: :reef,
      category: :keep_fresh,
      actions: [
        sub1: [repeat_for: [hours: 2], on: "switch", sleep: [minutes: 1]],
        sub2: [
          oneshot: true,
          off: "switch2",
          sleep: [seconds: 20],
          on: "switch2",
          sleep: [seconds: 56]
        ],
        sub3: [cycles: 200, sleep: [seconds: 45], on: "switch3"],
        sub4: [
          infinity: true,
          sleep: [minutes: 5],
          on: "switch3",
          sleep: [minutes: 3, off: "switch3"]
        ]
      ]
    ]
  end

  # def heat_standby do
  #   [
  #     {swmt(), swmt() |> ths_activate(standby())},
  #     {dt(), dt() |> ths_activate(standby())}
  #   ]
  # end
  #
  #
  # def heat(p) when is_binary(p), do: ths_activate(swmt(), p)
  #
  # def heat(_), do: print_usage("mix_heat", "profile")
  #

  # def resume_display_tank, do: ths_activate(dt(), "75F")

  # def water_change_begin(opts \\ [check_diff: true, interactive: true])

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
  #     swmt() |> ths_activate(standby())
  #     display_tank() |> ths_activate(standby())
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
  #   swmt() |> ths_activate(standby())
  #   display_tank() |> ths_activate("75F")
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
  # defp print_heading(text) when is_binary(text) do
  #   IO.puts(" ")
  #   IO.puts(light_yellow() <> underline() <> text <> reset())
  #   IO.puts(" ")
  # end
  #

  #
  # defp sensor_status(name) do
  #   temp_format = fn sensor ->
  #     temp = Sensor.fahrenheit(name: sensor, since_secs: 30)
  #
  #     if is_nil(temp) do
  #       temp
  #     else
  #       Float.round(temp, 1)
  #     end
  #   end
  #
  #   %{
  #     subsystem: name,
  #     status: temp_format.(name),
  #     active: "-"
  #   }
  # end
  #
  # def th_status(name, _opts) do
  #   with active_profile when is_struct(active_profile) <-
  #          Thermostat.Server.profiles(name, active: true) do
  #     %{
  #       subsystem: name,
  #       status: active_profile |> Map.get(:name),
  #       active: "-"
  #     }
  #   else
  #     error -> inspect(error, pretty: true) |> IO.puts()
  #   end
  # end
  #
  # # constants
  # defp display_tank, do: "display tank"
  # defp dt, do: display_tank()
  # defp dt_sensor, do: "display_tank"
  # defp swmt, do: "mix tank"
  # defp swmt_sensor, do: "mixtank"
end
