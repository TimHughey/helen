defmodule MsgTestHelper do
  @moduledoc false

  @host_default "ruth.generic"
  @remote_name_default "remote-generic"

  @pios 12
  @states_default for x <- 0..@pios, do: %{pio: x, state: false}

  def add_device(payload, opts) do
    device = opts[:device] || device_default()

    put_in(payload, [:device], device)
  end

  def device_default, do: "dev/generic"

  def make_payload(opts) when is_list(opts) do
    import Helen.Time.Helper, only: [unix_now: 1]
    import Msgpax, only: [pack!: 2]

    host = opts[:host] || @host_default
    name = opts[:remote_name] || @remote_name_default
    mtime = opts[:mtime] || unix_now(:second)

    type = opts[:type] || "type_missing"

    %{host: host, name: name, mtime: mtime, type: type}
    |> populate_payload(opts)
    |> pack!(iodata: false)
  end

  def make_topic(host) do
    ["test", "r", host]
  end

  def mqtt_msg(opts) do
    import Helen.Time.Helper, only: [utc_now: 0]

    msg_recv_dt = opts[:msg_recv_dt] || utc_now()
    host = opts[:host] || @host_default

    %{
      payload: make_payload(opts),
      topic: make_topic(host),
      host: host,
      msg_recv_dt: msg_recv_dt
    }
  end

  def populate_payload(%{type: "switch"} = payload, opts) do
    cmdack = opts[:ack] || false
    refid = opts[:refid] || false
    states = opts[:states] || @states_default
    log_reading = opts[:log_reading] || false

    payload =
      if cmdack,
        do: put_in(payload, [:cmdack], true) |> put_in([:latency_us], 30),
        else: payload

    payload = if refid, do: put_in(payload, [:refid], refid), else: payload
    payload = put_in(payload, [:log_reading], log_reading)

    payload = put_in(payload, [:pio_count], length(states))
    payload = put_in(payload, [:states], states)
    payload = put_in(payload, [:dev_latency_us], 100)
    payload = put_in(payload, [:read_us], 10)

    add_device(payload, opts)
  end

  def process_msg(msg, opts) do
    import Mqtt.Inbound, only: [init: 1, handle_call: 3]
    {:ok, state} = init(%{})
    async = opts[:async] || :unspecified

    opts = if async == :unspecified, do: opts ++ [async: false], else: opts

    {:reply, :ok, s} = handle_call({:incoming_msg, msg, opts}, self(), state)

    s
  end

  def switch_msg(opts) do
    put_in(opts, [:type], "switch") |> mqtt_msg()
  end
end
