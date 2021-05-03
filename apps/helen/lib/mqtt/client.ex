defmodule Mqtt.Client do
  @moduledoc false

  require Logger
  use GenServer

  alias Tortoise.Connection

  import Application, only: [get_env: 2, get_env: 3]

  #  def child_spec(opts) do
  #      id: Mqtt.Client,
  #      start: {Mqtt.Client, :start_link, [opts]},
  #      restart: :permanent,
  #      shutdown: 5000,
  #      type: :supervisor
  #    }
  #  end

  @feed_prefix get_env(:helen, :feeds, []) |> Keyword.get(:prefix, "dev")

  ## Callbacks

  ##
  ## Connection State API (for Handler)
  def connected do
    GenServer.cast(__MODULE__, {:connected})
  end

  def disconnected do
    GenServer.cast(__MODULE__, {:disconnected})
  end

  def terminated do
    GenServer.cast(__MODULE__, {:terminated})
  end

  ##
  ## GenServer Start and Initialization
  ##

  @impl true
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
  end

  def start_link(s) when is_map(s) do
    GenServer.start_link(__MODULE__, s, name: __MODULE__)
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

    case Msgpax.pack(msg_map) do
      {:ok, payload} ->
        msg = {:publish, feed, payload, pub_opts}
        GenServer.call(__MODULE__, msg)

      x ->
        report_publish_error(x)
    end
  end

  @impl true
  def handle_call({:publish, feed, payload, pub_opts} = msg, _from, %{client_id: client_id} = s)
      when is_binary(feed) and is_list(pub_opts) do
    alias Mqtt.Client.Fact.Payload, as: Influx

    Influx.write_specific_metric(msg)

    {elapsed_us, pub_rc} =
      :timer.tc(fn ->
        Tortoise.publish(client_id, feed, payload, pub_opts)
      end)

    {:reply, pub_rc, Map.put(s, :last_pub_rc, elapsed_us: elapsed_us, rc: pub_rc)}
  end

  @impl true
  def handle_call(unhandled_msg, _from, s) do
    log_unhandled("call", unhandled_msg)
    {:reply, :ok, s}
  end

  @impl true
  def handle_cast({:connected}, s) do
    s = Map.put(s, :connected, true)
    Logger.debug(["mqtt endpoint connected"])

    # subscribe to the report feed
    feed = get_env(:helen, :feeds, []) |> Keyword.get(:rpt, nil)
    res = Connection.subscribe(s.client_id, [feed])

    s = Map.put(s, :rpt_feed_subscribed, res)

    {:noreply, s}
  end

  @impl true
  def handle_cast({:disconnected}, s) do
    Logger.warn(["mqtt endpoint disconnected"])
    s = Map.put(s, :connected, false)
    {:noreply, s}
  end

  @impl true

  def handle_cast({:terminated}, s) do
    Logger.warn(["mqtt endpoint terminated"])
    s = Map.put(s, :connected, false)
    {:noreply, s}
  end

  @impl true
  def handle_cast(unhandled_msg, s) do
    log_unhandled("cast", unhandled_msg)
    {:noreply, s}
  end

  @impl true
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

  @impl true
  def handle_info(unhandled_msg, s) do
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
    import Helen.Time.Helper, only: [unix_now: 1]

    # append the current time (in unix seconds since epoch)
    # to the topic (feed).  the remote device can use this information
    # to assess if the message is current.
    mtime = unix_now(:second) |> Integer.to_string()
    {[@feed_prefix, host, subtopic, mtime] |> Enum.join("/"), 1}
  end

  defp log_unhandled(type, message) do
    Logger.warn([
      "unhandled ",
      inspect(type, pretty: true),
      " message ",
      inspect(message, pretty: true)
    ])
  end

  defp report_publish_error(e) do
    case e do
      {rc, error} ->
        [
          "publish() unable to pack payload: ",
          inspect(rc),
          " ",
          inspect(error, pretty: true)
        ]
        |> Logger.warn()

        {rc, error}

      catchall ->
        [
          "publish() unhandled error: ",
          inspect(catchall, pretty: true)
        ]
        |> Logger.warn()

        {:error, catchall}
    end
  end
end
