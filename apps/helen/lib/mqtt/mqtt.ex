defmodule Mqtt do
  require Logger

  @default_feeds Application.compile_env(:helen, :feeds) || []
  @default_server Mqtt.Client

  def call(%{invalid: invalid_msg} = msg) do
    Logger.warn("publish call failed: #{invalid_msg}")
    {:pack_failed, msg}
  end

  def call(%{topic: topic, payload: payload, pub_opts: pub_opts} = msg) do
    server = pub_opts[:server] || @default_server

    pid = Process.whereis(server)

    (pid && GenServer.call(pid, {:publish, topic, payload, pub_opts})) || {:no_server, msg}
  end

  def check_pack_result(%{pack_rc: {:error, exception}} = msg) do
    put_in(msg, [:invalid], inspect(exception))
  end

  def make_host_topic(%{host: host, device: device}, opts) do
    import Enum, only: [join: 2]
    import Helen.Time.Helper, only: [unix_now: 2]

    # NOTE:
    # the final topic is composed of:

    # 1. topic prefix is either found in opts or defaults to compile time env
    # 2. host from cmd map argument
    # 2. the subtopic is the device prefix: pwm/specific_device
    # 3. mtime is used by the remote host to assess is message is current.

    subtopic = String.split(device, "/") |> hd()
    parts = [prefix(opts), host, subtopic, unix_now(:second, as: :string)]
    join(parts, "/")
  end

  def prefix(opts) do
    opts[:prefix] || get_in(@default_feeds, [:prefix]) || "dev"
  end

  def publish(%{} = msg, opts) do
    import Msgpax, only: [pack: 1]

    opts = (opts[:pub_opts] || []) |> Keyword.put_new(:qos, 1)

    %{topic: make_host_topic(msg, opts), pack_rc: pack(msg), pub_opts: opts || []}
    |> validate_pack()
    |> call()
  end

  def seen_topics do
    %{seen_topics: topics} = :sys.get_state(Mqtt.Inbound)

    MapSet.to_list(topics) |> Enum.sort()
  end

  def validate_pack(%{pack_rc: {:ok, payload}} = msg) do
    Map.delete(msg, :pack_rc) |> put_in([:payload], payload)
  end

  def wait_for_roundtrip_ref(ref) do
    case GenServer.call(Mqtt.Inbound, {:wait_for_roundtrip_ref, ref}) do
      :already_received ->
        ref

      :added_to_waiters ->
        receive do
          {{Mqtt.Inbound, :roundtrip}, ^ref} when is_binary(ref) -> ref
        after
          1000 ->
            IO.puts("roundtrip reference never received")
        end
    end
  end
end
