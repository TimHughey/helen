defmodule RuthSim.Mqtt do
  require Logger

  @default_server MqttClient

  def add_roundtrip_ref(ctx, opts \\ [wait_for_roundtrip: true]) do
    if opts[:wait_for_roundtrip] == true do
      put_in(ctx, [:roundtrip_ref], Ecto.UUID.generate())
    else
      ctx
    end
  end

  def call(%{pack_rc: {_rc, reason}}) do
    Logger.warn("publish call failed: #{reason}")
    {:pack_failed, reason}
  end

  def call(server_msg) when is_map(server_msg) do
    server = server_msg[:pub_opts][:server] || @default_server

    pid = Process.whereis(server)

    (pid && GenServer.call(pid, server_msg)) || {:no_server, server_msg}
  end

  def publish(%{host: host} = msg, opts) do
    opts = (opts[:pub_opts] || []) |> Keyword.put_new(:qos, 1)

    msg[:roundtrip_ref] && Logger.debug(["\n", inspect(msg, pretty: true)])

    %{pack_rc: Msgpax.pack(msg), pub_opts: opts, host: host, cmdack: true}
    |> validate_pack()
    |> call()
  end

  def validate_pack(%{pack_rc: {:ok, x}} = server_msg) do
    Map.delete(server_msg, :pack_rc) |> put_in([:packed], x)
  end

  def validate_pack(server_msg), do: server_msg
end
