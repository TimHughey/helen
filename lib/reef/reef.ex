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

  alias Reef.Captain.Server, as: Captain
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

  defdelegate all_stop, to: Captain

  defdelegate ato_state, to: DisplayTank.Ato, as: :state

  defdelegate clean, to: Captain

  def clean_status, do: state(:clean)

  def default_opts do
    defs = [
      fill: [
        steps: [
          main: [
            run_for: "PT7H",
            on: [for: "PT2M"],
            off: [for: "PT16M"]
          ],
          topoff: [
            run_for: "PT1",
            on: [for: "PT10M"],
            off: [for: "PT1M"]
          ],
          finally: [msg: {:handoff, :keep_fresh}]
        ]
      ],
      keep_fresh: [
        air: [leader: true, on: [for: "PT7M"], off: [for: "PT3M"]],
        pump: [on: [for: "PT1M"], at_cmd_finish: :off]
      ],
      clean: [off: [for: "PT2H", at_cmd_finish: :on]]
    ]

    opts(fn _x -> defs end)
  end

  def test_opts do
    defs = [
      fill: [
        steps: [
          main: [
            run_for: "PT10S",
            on: [for: "PT0.5S"],
            off: [for: "PT1.2S"]
          ],
          topoff: [
            run_for: "PT10S",
            on: [for: "PT2S"],
            off: [for: "PT0.5S"]
          ],
          finally: [msg: {:handoff, :keep_fresh}]
        ]
      ],
      keep_fresh: [
        air: [leader: true, on: [for: "PT10S"], off: [for: "PT5S"]],
        pump: [on: [for: "PT1S"], at_cmd_finish: :off]
      ],
      clean: [off: [for: "PT15S", at_cmd_finish: :on]]
    ]

    opts(fn _x -> defs end)
  end

  def fill(opts \\ []), do: Captain.fill(opts)

  defdelegate fill_status, to: Captain

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
