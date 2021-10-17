defmodule Garden.Server do
  require Logger
  use GenServer

  alias Garden.{CmdDef, Config, State}
  alias Garden.Equipment.Check

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__, restart: :permanent)
  end

  @impl true
  def init(args) do
    cfg_file = [System.get_env("HELEN_BASE"), args[:cfg_file]] |> Path.join()
    cfg = Config.Decode.file_to_map(cfg_file) |> Config.new()

    {:ok, State.new(cfg), {:continue, :check_equipment}}
  end

  @impl true
  def handle_continue(:ready, %State{} = s), do: handle_info(:wakeup, s)

  @impl true
  # called once at startup to initiate checking of equipment availability
  def handle_continue(:check_equipment, %State{} = s), do: handle_info(:check_equipment, s)

  @impl true
  def handle_info(:check_equipment, %State{check: %Check{} = check} = s) do
    s = Check.check_status(check) |> State.update(s) |> State.mode(:checking_equipment)

    if Check.all_good?(s.check) do
      # good, all equipment reports ok status
      s |> State.mode(:ready) |> noreply_continue(:ready)
    else
      # equipment is not ready, keep checking after a delay
      Process.send_after(self(), :check_equipment, 1900)
      noreply(s)
    end
  end

  @impl true
  def handle_info(:wakeup, %State{} = s) do
    s |> control_equipment() |> schedule_wakeup() |> noreply()
  end

  @impl true
  def handle_info({Eva, :complete, _ref}, %State{} = s) do
    s |> noreply()
  end

  defp control_equipment(%State{cfg: %Config{cmds: cmd_defs} = cfg} = s) do
    alias Alfred.ExecResult

    now = Timex.now(cfg.timezone)
    equipment_cmds = Config.equipment_cmds(cfg, now)

    for {equipment, %{cmds: cmds, type: type}} <- equipment_cmds do
      case cmds do
        [] -> CmdDef.make_exec_cmd(equipment, "off", cmd_defs)
        [cmd] -> CmdDef.make_exec_cmd(equipment, cmd, cmd_defs)
      end
      |> tap(fn ec -> if(ec.cmd == "on" and type == :irrigation, do: Alfred.on(cfg.irrigation_power)) end)
      |> Alfred.execute()
      |> tap(fn
        {:ok, %ExecResult{} = er} -> Logger.debug("OK #{er.name} #{er.cmd}")
        {:error, %ExecResult{} = er} -> Logger.warn("ERROR #{er.name} #{er.cmd}")
        {:unknown, %ExecResult{} = er} -> Logger.warn("UNKNOWN #{er.name}")
      end)
    end

    s
  end

  defp schedule_wakeup(%State{cfg: %Config{} = cfg} = s) do
    now = Timex.now(cfg.timezone)
    next_wake_ms = Config.next_wakeup_ms(cfg, now)

    Logger.debug("next wake up: #{next_wake_ms}")

    Process.send_after(self(), :wakeup, next_wake_ms) |> State.update_wakeup_timer(s)
  end

  defp noreply(%State{} = s), do: {:noreply, s}
  defp noreply_continue(%State{} = s, term), do: {:noreply, s, {:continue, term}}
end
