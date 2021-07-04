defmodule Mqtt.Inbound do
  @moduledoc false

  @log_opts [reading: false]
  @compile_opts Application.compile_env(:helen, Mqtt.Inbound)

  require Logger
  use GenServer

  def start_link(args) do
    GenServer.start_link(Mqtt.Inbound, args, name: Mqtt.Inbound)
  end

  @impl true
  def init(_args) do
    %{
      async: @compile_opts[:async] || true,
      log: log_opts(),
      messages_dispatched: 0,
      seen_topics: MapSet.new(),
      # round trip references seen and waiting processes
      roundtrip: %{}
    }
    |> reply_ok()
  end

  def handoff_msg(%{payload: payload, topic: _} = msg) when is_bitstring(payload) do
    alias Mqtt.Client.Fact.Payload, as: Influx

    Influx.write_specific_metric(msg)

    GenServer.cast(Mqtt.Inbound, {:incoming_msg, msg})
  end

  @impl true
  def handle_call({:incoming_msg, msg}, _from, s) when is_map(msg) do
    {:reply, :ok, incoming_msg(msg, s)}
  end

  @impl true
  # (1 of 2) the roundtrip reference has already been processed
  def handle_call({:wait_for_roundtrip_ref, ref}, _from, %{roundtrip: roundtrip} = s)
      when is_map_key(roundtrip, ref) do
    %{s | roundtrip: Map.delete(roundtrip, ref)} |> reply(:already_received)
  end

  @impl true
  # (2 of 2) the roundtrip reference hasn't been seen, add the caller to the waiter map
  def handle_call({:wait_for_roundtrip_ref, ref}, {pid, _ref}, s) do
    %{s | roundtrip: put_in(s.roundtrip, [ref], pid)} |> reply(:added_to_waiters)
  end

  @impl true
  def handle_call(catch_all, _from, s) do
    Logger.warn(["unknown handle_call(", inspect(catch_all, pretty: true), ")"])
    {:reply, {:bad_msg}, s}
  end

  @impl true
  def handle_cast({:incoming_msg, msg}, s) when is_map(msg) do
    {:noreply, incoming_msg(msg, s)}
  end

  @impl true
  def handle_cast({:notify_waiter, ref}, s) do
    case get_in(s.roundtrip, [ref]) do
      x when is_pid(x) and x != self() -> send(x, {{Mqtt.Inbound, :roundtrip}, ref})
      _x -> nil
    end

    %{s | roundtrip: Map.delete(s.roundtrip, ref)} |> noreply()
  end

  @impl true
  def handle_cast(catch_all, s) do
    Logger.warn(["unknown handle_cast(", inspect(catch_all, pretty: true), ")"])
    {:noreply, s}
  end

  @impl true
  def handle_info(catch_all, s) do
    Logger.warn(["unknown handle_info(", inspect(catch_all, pretty: true), ")"])
    {:noreply, s}
  end

  # this function returns the server state
  def incoming_msg(_msg, s), do: s

  @mtime_min Helen.Time.Helper.unix_now(:second) - 5

  def metadata(%{mtime: m, type: t, host: <<"ruth.", _rest::binary>>} = r)
      when is_integer(m) and m >= @mtime_min and is_binary(t) do
    Map.merge(r, %{metadata: :ok, processed: false}) |> Map.delete(:mtime)
  end

  def metadata(bad) do
    Logger.warn(["bad metadata ", inspect(bad, pretty: true)])
    %{metadata: :failed}
  end

  def metadata?(%{metadata: :ok}), do: true
  def metadata?(%{metadata: :failed}), do: false
  def metadata?(%{} = r), do: metadata(r) |> metadata?()

  #
  # Misc Helpers
  #

  # don't attempt to atomize structs
  def atomize_keys(%{} = x) when is_struct(x), do: x

  def atomize_keys(%{} = map) do
    map
    |> Enum.map(fn {k, v} -> {String.to_atom(k), atomize_keys(v)} end)
    |> Enum.into(%{})
  end

  # Walk the list and atomize the keys of
  # of any map members
  def atomize_keys([head | rest]) do
    [atomize_keys(head) | atomize_keys(rest)]
  end

  def atomize_keys(not_a_map) do
    not_a_map
  end

  #
  # new code as of 2021-05-03
  #

  defp log_opts do
    for {k, v} <- @log_opts, into: %{} do
      {k, @compile_opts[k] || v}
    end
  end

  defp noreply(state) when is_map(state) do
    {:noreply, state}
  end

  defp reply(state, msg) when is_map(state) do
    {:reply, msg, state}
  end

  defp reply_ok(state) do
    {:ok, state}
  end
end
