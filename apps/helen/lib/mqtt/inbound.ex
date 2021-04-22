defmodule Mqtt.Inbound do
  @moduledoc false

  require Logger
  use GenServer

  def start_link(s) do
    GenServer.start_link(Mqtt.Inbound, s, name: Mqtt.Inbound)
  end

  ## Callbacks

  def additional_message_flags(opts \\ []) when is_list(opts) do
    GenServer.call(__MODULE__, {:additional_message_flags, opts})
  end

  @impl true
  def init(s)
      when is_map(s) do
    Logger.debug(["init()"])

    s =
      Map.put_new(s, :log_reading, config(:log_reading, false))
      |> Map.put_new(:messages_dispatched, 0)
      |> Map.put_new(
        :additional_message_flags,
        config(:additional_message_flags,
          log_invalid_readings: true,
          log_roundtrip_times: true
        )
        |> Enum.into(%{})
      )

    {:ok, s}
  end

  def seen_topics do
    %{seen_topics: topics} = :sys.get_state(__MODULE__)

    MapSet.to_list(topics) |> Enum.sort()
  end

  # internal work functions

  def process(%{payload: payload, topic: _} = msg, opts \\ [])
      when is_bitstring(payload) and is_list(opts) do
    alias Mqtt.Client.Fact.Payload, as: Influx

    Influx.write_specific_metric(msg)

    async = Keyword.get(opts, :async, true)

    if async,
      do: GenServer.cast(Mqtt.Inbound, {:incoming_msg, msg, opts}),
      else: GenServer.call(Mqtt.Inbound, {:incoming_msg, msg, opts})
  end

  # GenServer callbacks
  @impl true
  def handle_call({:additional_message_flags, opts}, _from, s) do
    set_flags = opts[:set] || nil
    merge_flags = opts[:merge] || nil

    cond do
      opts == [] ->
        {:reply, s.additional_message_flags, s}

      is_list(set_flags) ->
        s = Map.put(s, :additional_flags, Enum.into(set_flags, %{}))
        {:reply, {:ok, s.additional_flags}, s}

      is_list(merge_flags) ->
        flags =
          Map.merge(s.additional_message_flags, Enum.into(merge_flags, %{}))

        s = Map.put(s, :additional_flags, flags)
        {:reply, {:ok, s.additional_flags}, s}

      true ->
        {:reply, :bad_opts, s}
    end
  end

  @impl true
  def handle_call({:incoming_msg, msg, opts}, _from, s) when is_map(msg) do
    {:reply, :ok, incoming_msg(msg, s, opts)}
  end

  @impl true
  def handle_call(catch_all, _from, s) do
    Logger.warn(["unknown handle_call(", inspect(catch_all, pretty: true), ")"])
    {:reply, {:bad_msg}, s}
  end

  @impl true
  def handle_cast({:incoming_msg, msg, opts}, s) when is_map(msg) do
    {:noreply, incoming_msg(msg, s, opts)}
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

  defp config(key, default) when is_atom(key) do
    import Application, only: [get_env: 2]
    get_env(:helen, Mqtt.Inbound) |> Keyword.get(key, default)
  end

  def incoming_msg(%{payload: msgpack} = msg, %{} = s, opts)
      when is_bitstring(msgpack) do
    #
    # NOTE must return the state
    #

    with {:ok, r} <- Msgpax.unpack(msgpack),
         # drop the payload from the msg since it has been decoded
         # this allows the subsequent call to incoming_msg to match on
         # the decoded / unpacked message
         msg <- Map.drop(msg, [:payload]),
         # NOTE: Msgpax.unpack() returns maps with binaries as keys so let's
         #       convert them to atoms
         msg <- Map.merge(msg, atomize_keys(r)) do
      incoming_msg(msg, s, opts)
    else
      anything ->
        err_msg =
          ["parse failure:\n", inspect(anything)] |> IO.iodata_to_binary()

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
  def incoming_msg(%{topic: topic} = msg, s, opts) do
    with %{metadata: :ok} = r <- metadata(msg),
         # begin populating the message (aka Reading) with various
         # flags

         # log is a bool that directs downstream if logging
         # should occur for this message.  the value from the
         # message takes precedence.  if unspecifed then the
         # config option from the state is used.
         log_reading <- Map.get(r, :log, s.log_reading),
         # runtime_metrics consists of various configuration
         # items for downstream processing.  for consistency, if
         # the incoming message does not contain this key look in opts
         # passed to this function.  finally, if not in the opts default
         # to false
         runtime_metrics <- Keyword.get(opts, :runtime_metrics, false),
         # the base of the extra msg (reading) flags are the additional
         # message flags present in the state.  these flags are initially
         # from the configuration (or defaults) however could have been
         # changed at runtime.

         # we also include log_reading and runtime_metrics
         extra <-
           Map.get(s, :additional_message_flags, %{})
           |> Map.put(:log_reading, log_reading)
           |> Map.put(:runtime_metrics, runtime_metrics),
         # final step in populating the msg (reading) for processing is to
         # merge in th extra flags

         # NOTE
         # the msg (reading) is merged INTO the extra opts to avoid
         # overriding existing values
         r <- Map.merge(extra, r),
         # capture some MQTT metrics for operations
         s <- track_topics(s, msg) |> track_messages_dispatched() do
      # now hand off the message for processing

      # NOTE
      # the new state is returned by msg_proces
      msg_process(s, r, opts)
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

  def incoming_msg(%{parse_failure: parse_err}, state, _opts) do
    ["incoming msg parse err: ", inspect(parse_err, pretty: true)]
    |> Logger.warn()

    state
  end

  def incoming_msg(msg, state, _opts) do
    ["incoming_msg unmatched:\n", inspect(msg, pretty: true)] |> Logger.info()

    state
  end

  defp msg_process(%{} = state, %{type: type, topic: topic} = r, opts) do
    # unless specified in opts, we process "heavy" messages async
    # include async in the actual message (reading) for downstream
    async = Keyword.get(opts, :async, true)
    r = Map.put(r, :async, async)

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

    # NOTE
    #  must return the state
    state
  end

  defp msg_switch(%{async: async} = msg) do
    process = fn ->
      Switch.handle_message(msg) |> check_msg_fault()
    end

    if async do
      Task.start(process)
    else
      process.()
    end
  end

  defp msg_pwm(%{async: async} = msg) do
    process = fn ->
      PulseWidth.handle_message(msg) |> check_msg_fault()
    end

    if async do
      Task.start(process)
    else
      process.()
    end
  end

  defp msg_remote(%{async: async} = msg) do
    process = fn ->
      Remote.handle_message(msg) |> check_msg_fault()
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
      Sensor.handle_message(msg) |> check_msg_fault()
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

  defp track_topics(%{} = s, %{} = msg) do
    topics = Map.get(s, :seen_topics, MapSet.new())
    topic_list = Map.get(msg, :topic, ["not", "in", "msg"])

    topics = MapSet.put(topics, Enum.join(topic_list, "/"))

    Map.put(s, :seen_topics, topics)
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
    |> Logger.warn()

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
end
