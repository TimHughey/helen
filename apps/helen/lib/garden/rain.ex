defmodule Rain do
  require Logger

  def now(opts) do
    Switch.off_names_begin_with("irrigation")
    Process.sleep(500)

    power_switch = "irrigation 12v power"
    Switch.toggle(power_switch)

    Task.async(fn ->
      irrigation_tasks = [flower_box_task(opts), garden_task(opts)]

      for %Task{} = t <- irrigation_tasks do
        Task.await(t, :infinity)
      end

      power_status = Switch.toggle(power_switch) |> switch_status()
      Logger.info("irrigation complete, #{power_switch} #{power_status}")
    end)

    :ok
  end

  def flower_box_task(opts) do
    irrigate("irrigation flower boxes", opts[:boxes])
  end

  def garden_task(opts) do
    irrigate("irrigation garden", opts[:garden])
  end

  defp irrigate(switch_name, minutes) when is_integer(minutes) do
    location = String.split(switch_name, " ") |> tl() |> Enum.join(" ")
    Logger.info("irrigating #{location} for #{minutes} minutes")

    duration_ms = minutes * 60 * 1000

    Task.async(fn ->
      Switch.toggle(switch_name)
      Process.sleep(duration_ms)
      Switch.toggle(switch_name)
      Process.sleep(1000)

      status = Switch.position(switch_name) |> switch_status()
      Logger.info("#{switch_name} #{status}")
    end)
  end

  defp irrigate(_switch_name, nil), do: nil

  defp switch_status(status) do
    case status do
      {:ok, false} -> "OFF"
      {:ok, true} -> "ON"
      {:pending, details} -> if details[:position], do: "PENDING ON", else: "PENDING OFF"
      error -> "ERROR: #{inspect(error)}"
    end
  end
end
