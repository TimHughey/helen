defmodule RuthSim.Mqtt.Client do
  @moduledoc false

  alias __MODULE__

  defstruct client_id: nil, last_ref: nil, rpt_topic: nil, qos1: %{}

  require Logger
  use GenServer

  ##
  ## GenServer Start and Initialization
  ##

  @impl true
  def init(opts) do
    rpt_topic = [opts[:prefix], "r"] |> Enum.join("/")

    %Client{client_id: opts[:client_id], rpt_topic: rpt_topic}
    |> reply_ok()
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def handle_call(%{packed: packed, host: host, pub_opts: pub_opts}, from, s) do
    topic = [s.rpt_topic, host] |> Enum.join("/")

    {rc, ref} = Tortoise.publish(s.client_id, topic, packed, pub_opts)

    res = %{rc: rc, ref: ref, rpt_topic: topic, client_id: s.client_id}

    %{s | last_ref: ref}
    |> add_ref_to_qos1(from)
    |> reply(res)
  end

  @impl true
  def handle_call(unhandled_msg, _from, s) do
    ["unhandled call: ", inspect(unhandled_msg)] |> Logger.info()
    reply(s, :ok)
  end

  @impl true
  def handle_cast(_unhandled_msg, s), do: noreply(s)

  @impl true
  def handle_info({{Tortoise, _client_id}, ref, rc}, s) when rc == :ok do
    case get_in(s.qos1, [ref]) do
      %{send_reply: false} -> nil
      %{reply_to: reply_to} -> send(reply_to, {{Client, :msg_published}, ref, rc})
      _ -> nil
    end

    %{s | qos1: Map.delete(s.qos1, ref)}
    |> noreply()
  end

  @impl true
  def handle_info({{Tortoise, _client_id}, ref, rc}, s) do
    Logger.warn("publish reference error: #{inspect(rc)} ref: #{inspect(ref)}")

    noreply(s)
  end

  @impl true
  def handle_info(unhandled_msg, s) do
    ["unhandled info: ", inspect(unhandled_msg)] |> Logger.info()

    noreply(s)
  end

  defp add_ref_to_qos1(%Client{} = s, nil = _from), do: s

  defp add_ref_to_qos1(%Client{last_ref: ref} = s, {pid, _} = _from) do
    %{s | qos1: put_in(s.qos1, [ref], %{reply_to: pid, send_reply: false})}
  end

  defp noreply(%Client{} = s), do: {:noreply, s}
  defp reply(%Client{} = s, msg), do: {:reply, msg, s}
  defp reply(msg, %Client{} = s), do: {:reply, msg, s}
  defp reply_ok(%Client{} = s), do: {:ok, s}
end
