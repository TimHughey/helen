defmodule Sally.MsgOut do
  alias __MODULE__

  # @server_default Sally.Mqtt.Client
  @publish_defaults Application.compile_env!(:sally, [Sally.MsgOut, :publish])

  defstruct host: nil,
            device: nil,
            data: %{},
            topic: nil,
            opts: [],
            packed: nil,
            qos: @publish_defaults[:qos],
            server: nil

  @type opts :: [qos: qos(), server: module(), topic: String.t()]
  @type qos :: [0..2]

  @type t :: %__MODULE__{
          host: String.t(),
          device: String.t(),
          data: map(),
          topic: String.t(),
          opts: opts(),
          packed: iodata(),
          qos: qos(),
          server: module()
        }

  def create(filters, data, opts) when is_list(filters) and is_map(data) do
    topic = ([@publish_defaults[:prefix]] ++ filters) |> Enum.join("/")
    %MsgOut{topic: topic, data: data, qos: opts[:qos] || @publish_defaults[:qos]} |> pack()
  end

  def create(data, %_{ident: ident, host: host}, opts) do
    %MsgOut{host: host, device: ident, data: data, opts: opts} |> apply_opts() |> ensure_topic() |> pack()
  end

  defp apply_opts(%MsgOut{} = mo) do
    %MsgOut{
      mo
      | topic: mo.opts[:topic] || mo.topic,
        qos: mo.opts[:qos] || mo.qos,
        server: mo.opts[:server] || mo.server
    }
  end

  defp ensure_topic(%MsgOut{} = mo) do
    prefix = @publish_defaults[:prefix]
    now_bin = System.os_time(:second) |> to_string()

    # 1. topic wasn't specified
    # 2. topic was specified, pass through
    case mo.topic do
      nil -> %MsgOut{mo | topic: [prefix, mo.host, mo.device, now_bin] |> Enum.join("/")}
      _ -> mo
    end
  end

  defp pack(%MsgOut{data: data} = mo) do
    case data do
      x when is_map(x) or is_list(x) -> %MsgOut{mo | packed: Msgpax.pack!(x)}
      _ -> mo
    end
  end
end
