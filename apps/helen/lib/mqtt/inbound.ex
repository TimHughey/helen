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
  def handle_cast({:notified_waiter, ref}, s) do
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

  def incoming_msg(%{payload: packed} = msg, s) when is_bitstring(packed) do
    #
    # NOTE must return the state
    #
    with {:ok, r} <- Msgpax.unpack(packed),
         # drop the payload from the msg since it has been decoded
         # this allows the subsequent call to incoming_msg to match on
         # the decoded / unpacked message
         msg <- Map.drop(msg, [:payload]),
         # NOTE: Msgpax.unpack() returns maps with binaries as keys so let's
         #       convert them to atoms
         msg <- Map.merge(msg, atomize_keys(r)),
         s <- add_roundtrip_ref_if_needed(s, msg[:roundtrip_ref]) do
      incoming_msg(msg, s)
    else
      anything ->
        err_msg = ["parse failure:\n", inspect(anything)] |> IO.iodata_to_binary()

        Logger.warn(err_msg)

        Map.put(s, :parse_failure, err_msg)
    end
  end

  # incoming_msg is invoked by the handle_* callbacks to:
  #  a. unpack / decode the raw payload
  #  b. validate the message format via Reading
  #  c. populate the message with necessary flags for downstream processing
  #
  # if steps (a) and (b) are successful then the message is passed
  # to msg_process
  #
  # this function returns the server state
  def incoming_msg(%{topic: topic} = msg, s) do
    with %{metadata: :ok} = r <- metadata(msg),
         r <- put_in(r, [:log_reading], r[:log] || s.log.reading),
         s <- track_topics(s, msg) |> track_messages_dispatched() do
      # NOTE
      # the new state is returned by msg_process
      msg_process(s, r)
    else
      # metadata failed checks
      {:ok, %{metadata: :failed}} ->
        ["metadata failed topic=\"", Enum.join(topic, "/"), "\""]
        |> Logger.warn()

        s

      # MsgPax or Jason error
      {:error, _error} ->
        ["unpack/decode failed topic=\"", Enum.join(topic, "/"), "\""]
        |> Logger.warn()

        s

      anything ->
        ["incoming message error: \n", inspect(anything, pretty: true)]
        |> Logger.info()

        s
    end
  end

  def incoming_msg(%{parse_failure: parse_err}, state) do
    ["incoming msg parse err: ", inspect(parse_err, pretty: true)]
    |> Logger.warn()

    state
  end

  def incoming_msg(msg, state) do
    ["incoming_msg unmatched:\n", inspect(msg, pretty: true)] |> Logger.info()

    state
  end

  # (2 of 2) no waiter for this roundtrip ref yet, add it
  defp add_roundtrip_ref_if_needed(%{roundtrip: roundtrip} = s, rt_ref)
       when is_binary(rt_ref) and not is_map_key(roundtrip, rt_ref) do
    %{s | roundtrip: put_in(roundtrip, [rt_ref], :received)}
  end

  # (2 of 2) either already in roundtrip or not a binary
  defp add_roundtrip_ref_if_needed(s, _), do: s

  # (1 of 2) there is a waiter for the roundtrip ref
  defp msg_post_process(%{roundtrip: roundtrip, roundtrip_ref: rt_ref} = msg)
       when is_map_key(roundtrip, rt_ref) do
    reply_to = get_in(roundtrip, [rt_ref])
    send(reply_to, {{Mqtt.Inbound, :roundtrip}, rt_ref})

    GenServer.cast(__MODULE__, {:notified_waiter, rt_ref})

    check_msg_fault(msg)
  end

  # (3 of 3) no roundtrip ref
  defp msg_post_process(msg), do: check_msg_fault(msg)

  # (1 of 2) populate msg with specific keys from state for use downstream and stop the propagation
  # of the state because the processing of the message itself could be async
  defp msg_process(state, r) do
    extra = Map.take(state, [:async, :roundtrip])

    Map.merge(extra, r) |> msg_process()

    state
  end

  # (2 of 2)
  defp msg_process(%{type: type, topic: topic} = r) do
    case type do
      type when type in ["switch"] ->
        msg_switch(r)

      type when type in ["pwm"] ->
        msg_pwm(r)

      type when type in ["text"] ->
        msg_remote_log(r)

      type when type in ["sensor"] ->
        msg_sensor(r)

      type when type in ["boot", "remote", "watcher"] ->
        msg_remote(r)

      type ->
        [
          "unknown message type=",
          inspect(type, pretty: true),
          " topic=",
          Enum.join(topic, "/") |> inspect(pretty: true)
        ]
        |> Logger.warn()
    end
  end

  defp msg_switch(%{async: async} = msg) do
    process = fn ->
      Switch.handle_message(msg) |> msg_post_process()
    end

    if async do
      Task.start(process)
    else
      process.()
    end
  end

  defp msg_pwm(%{async: async} = msg) do
    process = fn ->
      PulseWidth.handle_message(msg) |> msg_post_process()
    end

    if async do
      Task.start(process)
    else
      process.()
    end
  end

  defp msg_remote(%{async: async} = msg) do
    process = fn ->
      Remote.handle_message(msg) |> msg_post_process()
    end

    if async do
      Task.start(process)
    else
      process.()
    end
  end

  defp msg_remote_log(%{async: _async} = r) do
    # simply get the remote log message and log it locally
    name = Map.get(r, :name, "<no name>")
    text = Map.get(r, :text)

    # we only inspect values that aren't binary to avoid quoting
    ensure_binary = fn
      x when is_binary(x) -> x
      x -> inspect(x, pretty: true)
    end

    [ensure_binary.(name), " ", ensure_binary.(text)] |> Logger.info()

    # always return :ok
    :ok
  end

  defp msg_sensor(%{async: async} = msg) do
    process = fn ->
      Sensor.handle_message(msg) |> msg_post_process()
    end

    if async do
      Task.start(process)
    else
      process.()
    end
  end

  defp check_msg_fault(msg) do
    msg |> log_fault_if_needed() |> log_cmd_ack_fault_if_needed()
  end

  defp track_messages_dispatched(%{messages_dispatched: dispatched} = s),
    do: %{s | messages_dispatched: dispatched + 1}

  defp track_topics(s, %{} = msg) do
    topic = get_in(msg, [:topic]) || ["not", "in", "msg"]

    %{s | seen_topics: MapSet.put(s.seen_topics, Enum.join(topic, "/"))}
  end

  @mtime_min Helen.Time.Helper.unix_now(:second) - 5

  def metadata(%{mtime: m, type: t, host: <<"ruth.", _rest::binary>>} = r)
      when is_integer(m) and m >= @mtime_min and is_binary(t) do
    Map.merge(r, %{metadata: :ok, processed: false})
  end

  def metadata(bad) do
    Logger.warn(["bad metadata ", inspect(bad, pretty: true)])
    %{metadata: :failed}
  end

  def metadata?(%{metadata: :ok}), do: true
  def metadata?(%{metadata: :failed}), do: false
  def metadata?(%{} = r), do: metadata(r) |> metadata?()

  ##
  ## Logging Helpers
  ##

  defp log_cmd_ack_fault_if_needed(%{cmd_ack_fault: _fault} = msg) do
    # """
    # cmd ack fault:
    #   #{inspect(fault, pretty: true)}
    #
    # message:
    #     #{inspect(msg, pretty: true)}
    # """
    # |> Logger.warn()

    msg
  end

  defp log_cmd_ack_fault_if_needed(msg), do: msg

  defp log_fault_if_needed(%{fault: fault} = msg) do
    error = get_in(msg, [fault])

    """
    fault:
      #{inspect(fault, pretty: true)}

    error:
      #{inspect(error, pretty: true)}

    message:
      #{inspect(msg, pretty: true)}
    """
    |> Logger.debug()

    msg
  end

  defp log_fault_if_needed(msg), do: msg

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
