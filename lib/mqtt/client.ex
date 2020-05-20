defmodule Mqtt.Client do
  @moduledoc false

  require Logger
  use GenServer

  alias Tortoise.Connection

  import Application, only: [get_env: 2, get_env: 3]
  alias Mqtt.Timesync

  #  def child_spec(opts) do
  #
  #
  #      id: Mqtt.Client,
  #      start: {Mqtt.Client, :start_link, [opts]},
  #      restart: :permanent,
  #      shutdown: 5000,
  #      type: :supervisor
  #    }
  #  end

  @feed_prefix get_env(:helen, :feeds, []) |> Keyword.get(:prefix, "dev")

  def start_link(s) when is_map(s) do
    GenServer.start_link(__MODULE__, s, name: __MODULE__)
  end

  ## Callbacks

  def connected do
    GenServer.cast(__MODULE__, {:connected})
  end

  def disconnected do
    GenServer.cast(__MODULE__, {:disconnected})
  end

  #
  # forward/2:
  #   -publish a msg_map to the :feed in opts
  #   -does NOT call MessageSave
  #
  def forward(%{payload: payload, direction: :in, opts: opts} = inflight)
      when is_bitstring(payload) and is_list(opts) do
    # Logger.info(["forward/1 ", inspect(inflight, pretty: true)])
    GenServer.cast(__MODULE__, {:forward, inflight})
    {:ok}
  end

  def forward(bad_args) do
    Logger.warn(["forward/1 bad args: ", inspect(bad_args, pretty: true)])
    {:bad_args, bad_args}
  end

  def init(s) when is_map(s) do
    #
    ## HACK: clean up opts
    #
    log =
      get_env(:helen, Mqtt.Client, [])
      |> Keyword.get(:log, [])
      |> Keyword.get(:init, false)

    log &&
      Logger.info(["init() state: ", inspect(s, pretty: true)])

    s = Map.put_new(s, :runtime_metrics, false)

    if Map.get(s, :autostart, false) do
      # prepare the opts that will be passed to Tortoise and start it

      opts = config(:tort_opts) ++ [handler: {Mqtt.Handler, []}]
      {:ok, mqtt_pid} = Connection.start_link(opts)

      # populate the state and construct init() return
      new_state = %{
        mqtt_pid: mqtt_pid,
        client_id: Keyword.get(opts, :client_id),
        mqtt_env: @feed_prefix,
        opts: opts
      }

      s = Map.merge(s, new_state)

      Logger.debug(["MQTT via tortoise ", inspect(mqtt_pid)])

      {:ok, s}
    else
      # when we don't autostart the mqtt pid will be nil
      s = Map.put_new(s, :mqtt_pid, nil) |> Map.put_new(:client_id, nil)

      {:ok, s}
    end

    # init() return is calculated above in if block
    # at the conclusion of init() we have a running InboundMessage GenServer and
    # potentially a connection to MQTT
  end

  @doc """
    Publishes the passed map to the host specific MQTT feed

      ## Inputs
        1. msg_map
        2. subtopic
        3. optional opts:  [feed: {template_string, qos}, pub_opts: []]

      ## Examples
        iex> Mqtt.Client.publish_to_host(%{host: "xyz"}, "profile", opts)
  """

  @doc since: "0.0.8"
  def publish_to_host(%{host: host} = msg_map, subtopic, opts \\ [])
      when is_map(msg_map) and is_binary(subtopic) and is_list(opts) do
    default_feed = host_feed(host, subtopic)
    {feed, qos} = Keyword.get(opts, :feed, default_feed)
    pub_opts = Keyword.get(opts, :pub_opts, []) ++ [qos: qos]

    with {:ok, payload} <- Msgpax.pack(msg_map),
         save_msg <- %{payload: payload, direction: :out},
         %{payload: payload} <- MessageSave.save(save_msg) do
      GenServer.call(__MODULE__, {:publish, feed, payload, pub_opts})
    else
      e -> report_publish_error(e)
    end
  end

  def runtime_metrics, do: GenServer.call(__MODULE__, {:runtime_metrics})

  def runtime_metrics(flag) when is_boolean(flag) or flag == :toggle do
    GenServer.call(__MODULE__, {:runtime_metrics, flag})
  end

  def handle_call(
        {:publish, feed, payload, pub_opts},
        _from,
        %{autostart: true, client_id: client_id} = s
      )
      when is_binary(feed) and is_list(pub_opts) do
    {elapsed_us, pub_rc} =
      :timer.tc(fn ->
        Tortoise.publish(client_id, feed, payload, pub_opts)
      end)

    {:reply, pub_rc,
     Map.put(s, :last_pub_rc, elapsed_us: elapsed_us, rc: pub_rc)}
  end

  def handle_call(
        {:publish, feed, payload, pub_opts},
        _from,
        %{autostart: false} = s
      )
      when is_binary(feed) and is_list(pub_opts) do
    Logger.debug(["not started, dropping ", inspect(payload, pretty: true)])
    {:reply, :not_started, s}
  end

  def handle_call({:runtime_metrics}, _from, %{runtime_metrics: flag} = s),
    do: {:reply, flag, s}

  def handle_call({:runtime_metrics, flag}, _from, %{runtime_metrics: was} = s)
      when is_boolean(flag) or flag == :toggle do
    new_flag =
      if flag == :toggle do
        not s.runtime_metrics
      else
        flag
      end

    s = Map.put(s, :runtime_metrics, new_flag)

    {:reply, %{was: was, is: s.runtime_metrics}, s}
  end

  def handle_call(unhandled_msg, _from, s) do
    log_unhandled("call", unhandled_msg)
    {:reply, :ok, s}
  end

  def handle_cast({:connected}, s) do
    s = Map.put(s, :connected, true)
    Logger.debug(["mqtt endpoint connected"])

    # subscribe to the report feed
    feed = get_env(:helen, :feeds, []) |> Keyword.get(:rpt, nil)
    res = Connection.subscribe(s.client_id, [feed])

    s = Map.put(s, :rpt_feed_subscribed, res)

    s = start_timesync_task(s)

    {:noreply, s}
  end

  def handle_cast({:disconnected}, s) do
    Logger.warn(["mqtt endpoint disconnected"])
    s = Map.put(s, :connected, false)
    {:noreply, s}
  end

  def handle_cast(
        {:forward, %{payload: payload, direction: direction, opts: opts}},
        %{client_id: client_id} = s
      ) do
    forward_feed = get_in(opts, [:forward_opts, direction, :feed])

    rc =
      with {:ok, {feed, qos}} <- get_feed(forward_feed),
           pub_opts <- [qos: qos] ++ Keyword.get(opts, :pub_opts, []) do
        Tortoise.publish(client_id, feed, payload, pub_opts)
      else
        e ->
          report_publish_error(e)
      end

    {:noreply, Map.put(s, :last_forward_rc, rc)}
  end

  def handle_cast(unhandled_msg, s) do
    log_unhandled("cast", unhandled_msg)
    {:noreply, s}
  end

  def handle_info({{Tortoise, _client_id}, ref, res}, s) do
    log = Map.get(s, :log_subscriptions, false)

    log &&
      Logger.info([
        "subscription ref: ",
        inspect(ref, pretty: true),
        " res: ",
        inspect(res, pretty: true)
      ])

    {:noreply, s}
  end

  def handle_info(
        {ref, result} = msg,
        %{timesync: %{task: %{ref: timesync_ref}}} = s
      )
      when is_reference(ref) and ref == timesync_ref do
    Logger.debug([
      "handle_info(",
      inspect(msg, pretty: true),
      ", ",
      inspect(s, pretty: true)
    ])

    s = Map.put(s, :timesync, Map.put(s.timesync, :result, result))

    {:noreply, s}
  end

  def handle_info(
        {:DOWN, ref, :process, pid, reason} = msg,
        %{timesync: %{task: %{ref: timesync_ref}}} = s
      )
      when is_reference(ref) and is_pid(pid) do
    Logger.debug([
      "handle_info(",
      inspect(msg, pretty: true),
      ", ",
      inspect(s, pretty: true)
    ])

    s =
      if ref == timesync_ref do
        track =
          Map.put(s.timesync, :exit, reason)
          |> Map.put(:task, nil)
          |> Map.put(:status, :finished)

        Map.put(s, :timesync, track)
      end

    {:noreply, s}
  end

  def handle_info(unhandled_msg, _from, s) do
    log_unhandled("info", unhandled_msg)
    {:noreply, s}
  end

  #
  # PRIVATE
  #

  defp config(key)
       when is_atom(key) do
    get_env(:helen, Mqtt.Client) |> Keyword.get(key)
  end

  defp host_feed(host, subtopic) when is_binary(host) and is_binary(subtopic) do
    {[@feed_prefix, host, subtopic] |> Enum.join("/"), 1}
  end

  defp log_unhandled(type, message) do
    Logger.warn([
      "unhandled ",
      inspect(type, pretty: true),
      " message ",
      inspect(message, pretty: true)
    ])
  end

  defp get_feed(feed_opt) do
    case feed_opt do
      {feed, qos} when is_binary(feed) and qos in 0..2 ->
        {:ok, {feed, qos}}

      feed ->
        {:bad_feed, feed}
    end
  end

  defp report_publish_error(e) do
    case e do
      # {:ok, _res} ->
      #   # not an error, pass through "error"
      #   e

      {:bad_feed, bad_feed} ->
        Logger.warn([
          "publish() bad feed: ",
          inspect(bad_feed, pretty: true)
        ])

        Logger.warn(["hint: check :feeds are defined in the configuration"])

        {:bad_args, :feed_config_missing}

      {rc, error} ->
        Logger.warn([
          "publish() unable to pack payload: ",
          inspect(rc),
          " ",
          inspect(error, pretty: true)
        ])

        {rc, error}

      catchall ->
        Logger.warn([
          "publish() unhandled error: ",
          inspect(catchall, pretty: true)
        ])

        {:error, catchall}
    end
  end

  defp start_timesync_task(%{mqtt_env: mqtt_env, client_id: client_id} = s) do
    opts = Map.merge(timesync_opts(), %{feed: mqtt_env, client_id: client_id})
    task = Task.async(Timesync, :run, [opts])

    Map.put(s, :timesync, %{task: task, status: :started})
  end

  defp timesync_opts do
    get_env(:helen, Mqtt.Client, [])
    |> Keyword.get(:timesync, [])
    |> Enum.into(%{})
  end
end
