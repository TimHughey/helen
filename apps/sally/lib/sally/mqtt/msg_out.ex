defmodule Sally.MsgOut do
  alias __MODULE__

  @server_default Sally.Mqtt.Client
  @publish_defaults Application.compile_env!(:sally, [@server_default, :publish])

  @enforce_keys [:host, :device, :data]
  defstruct host: nil,
            device: nil,
            data: %{},
            topic: nil,
            packed: nil,
            qos: @publish_defaults[:qos],
            server: @server_default

  @type qos :: [0..2]

  @type t :: %__MODULE__{
          host: String.t(),
          device: String.t(),
          data: map(),
          topic: String.t(),
          packed: iodata(),
          qos: qos(),
          server: module()
        }

  def apply_opts(%MsgOut{} = mo, opts) do
    %MsgOut{
      mo
      | topic: opts[:topic] || mo.topic,
        qos: opts[:qos] || mo.qos,
        server: opts[:server] || mo.server
    }
  end

  # (1 of 2) topic already populated
  def ensure_topic(%MsgOut{topic: topic} = mo) when is_binary(topic), do: mo

  # (2 of 2) topic must be built
  def ensure_topic(%MsgOut{host: host, device: device}) when is_binary(host) and is_binary(device) do
    prefix = @publish_defaults[:prefix]
    [subtopic | _] = String.split(device, "/")
    now = System.os_time(:second) |> to_string()

    [prefix, host, subtopic, now] |> Enum.join("/")
  end

  def pack(%MsgOut{data: data} = mo) when is_map(data) and map_size(data) > 1 do
    payload = %{device: mo.device} |> Map.merge(data)

    Msgpax.pack!(payload)
  end
end
