defmodule Mqtt.InboundMessage do
  @moduledoc """
  """
  require Logger
  use GenServer
  import Application, only: [get_env: 2]
  import Process, only: [send_after: 3]

  alias Mqtt.Reading
  alias Fact.FreeRamStat
  alias Fact.RunMetric

  def start_link(s) do
    GenServer.start_link(Mqtt.InboundMessage, s, name: Mqtt.InboundMessage)
  end

  ## Callbacks

  def init(s)
      when is_map(s) do
    case Map.get(s, :autostart, false) do
      true -> send_after(self(), {:startup}, 0)
      false -> nil
    end

    s = Map.put_new(s, :log_reading, config(:log_reading))
    s = Map.put_new(s, :messages_dispatched, 0)
    s = Map.put_new(s, :json_log, nil)

    Logger.info("init()")

    {:ok, s}
  end

  @log_json_msg :log_json
  def log_json(args) do
    GenServer.cast(Mqtt.InboundMessage, {@log_json_msg, args})
  end

  # internal work functions

  def process(msg)
      when is_binary(msg) do
    GenServer.cast(Mqtt.InboundMessage, {:incoming_message, msg})
  end

  defp log_reading(%{}, false), do: nil

  defp log_reading(%{} = r, true) do
    if Reading.temperature?(r) do
      Logger.info(fn ->
        ~s(#{r.host} #{r.device} #{r.tc} #{r.tf})
      end)
    end

    if Reading.relhum?(r) do
      Logger.info(fn ->
        ~s(#{r.host} #{r.device} #{r.tc} #{r.tf} #{r.rh})
      end)
    end
  end

  # GenServer callbacks
  def handle_cast({:incoming_message, msg}, s)
      when is_binary(msg) and is_map(s) do
    {elapsed_us, _res} =
      :timer.tc(fn ->
        if is_pid(s.json_log) do
          log = "#{msg}\n"
          IO.write(s.json_log, log)
        end

        Reading.decode(msg) |> decoded_msg(s)
      end)

    s = %{s | messages_dispatched: s.messages_dispatched + 1}

    RunMetric.record(
      module: "#{__MODULE__}",
      application: "mercurial",
      metric: "msgs_dispatched",
      val: s.messages_dispatched
    )

    RunMetric.record(
      module: "#{__MODULE__}",
      metric: "mqtt_process_inbound_msg_us",
      device: "none",
      val: elapsed_us
    )

    {:noreply, s}
  end

  # open the json log if not already open
  def handle_cast({@log_json_msg, true}, %{json_log: nil} = s) do
    {rc, json_log} = File.open("/tmp/json.log", [:append, :utf8])

    if rc == :ok do
      Logger.info(fn -> "json log opened" end)
    end

    s = %{s | json_log: json_log}

    {:noreply, s}
  end

  # if the json log is already open don't do anything
  def handle_cast({@log_json_msg, true}, %{json_log: pid} = s)
      when is_pid(pid) do
    {:noreply, s}
  end

  # if the json log is open then close it
  def handle_cast({@log_json_msg, false}, %{json_log: pid} = s)
      when is_pid(pid) do
    :ok = File.close(pid)

    s = %{s | json_log: nil}

    {:noreply, s}
  end

  # if the json log is already closed then do nothing
  def handle_cast({@log_json_msg, false}, %{json_log: nil} = s) do
    {:noreply, s}
  end

  def handle_info({:startup}, s)
      when is_map(s) do
    send_after(self(), {:periodic_log}, config(:periodic_log_first_ms))
    Logger.info(fn -> "startup()" end)

    {:noreply, s}
  end

  def handle_info({:periodic_log}, s)
      when is_map(s) do
    Logger.info(fn -> "messages dispatched: #{s.messages_dispatched}" end)

    send_after(self(), {:periodic_log}, config(:periodic_log_ms))

    {:noreply, s}
  end

  defp config(key)
       when is_atom(key) do
    get_env(:mcp, Mqtt.InboundMessage) |> Keyword.get(key)
  end

  defp decoded_msg({:ok, r}, s) do
    log_reading(r, s.log_reading)

    if Reading.startup?(r) do
      {mod, func} = config(:startup_msgs)

      # invoke the configured module to process startup messages
      apply(mod, func, [r])
    end

    if Reading.temperature?(r) || Reading.relhum?(r) do
      {mod, func} = config(:temperature_msgs)

      # invoke the configured module to process the incoming sensor msg
      apply(mod, func, [r])
    end

    if Reading.switch?(r) do
      {mod, func} = config(:switch_msgs)
      # if not Reading.cmdack?(r), do: Logger.info(msg)

      # invoke the configured module to process the incoming switch msg
      apply(mod, func, [r])
    end

    if Reading.free_ram_stat?(r) do
      # Logger.info("#{msg}")
      FreeRamStat.record(remote_host: r.host, val: r.freeram)
    end

    nil
  end

  defp decoded_msg({:error, e}, _s) do
    Logger.warn(fn -> e end)
  end
end