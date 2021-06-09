defmodule Sally.Host.Reply do
  defmodule State do
    require Logger

    alias __MODULE__

    defstruct last_pub: nil

    @type pub_elapsed_us() :: pos_integer()
    @type last_pub() :: {:ok, reference()} | :ok

    @type t :: %__MODULE__{last_pub: last_pub()}

    def save_last_pub(msg, %State{} = s), do: {%State{s | last_pub: msg}, msg}
  end

  require Logger
  use GenServer, restart: :permanent, shutdown: 1000

  alias __MODULE__
  alias Sally.Host.Reply.State

  @client_id Application.compile_env!(:sally, [:mqtt_connection, :client_id])
  @qos_default Application.compile_env!(:sally, [Reply, :publish, :qos])
  @prefix Application.compile_env!(:sally, [Reply, :publish, :prefix])

  defstruct client_id: @client_id,
            ident: nil,
            name: nil,
            data: %{},
            filter: nil,
            opts: [],
            packed_length: 0,
            pub_ref: nil,
            qos: @qos_default

  ##
  ## Public API
  ##
  def send(%Reply{} = msg) do
    {:send, msg |> make_topic_filter() |> set_qos()} |> Reply.call()
  end

  @impl true
  def init(_) do
    %State{} |> reply_ok()
  end

  def start_link(_) do
    GenServer.start_link(Reply, [], name: __MODULE__)
  end

  @impl true
  def handle_call({:send, %Reply{} = msg}, _from, %State{} = s) do
    packed = Msgpax.pack!(msg.data)

    Tortoise.publish(msg.client_id, msg.filter, packed, qos: msg.qos)
    |> save_pub_rc(msg)
    |> save_packed_length(IO.iodata_length(packed))
    |> State.save_last_pub(s)
    |> reply()
  end

  @impl true
  def handle_info({{Tortoise, _client_id}, _ref, _res}, %State{} = s) do
    s |> noreply()
  end

  ##
  ## GenServer Call / Cast Helpers
  ##

  @doc false
  def call(msg) when is_tuple(msg) do
    case GenServer.whereis(Reply) do
      x when is_pid(x) -> GenServer.call(x, msg)
      x -> {:no_server, x}
    end
  end

  defp make_topic_filter(%Reply{} = msg) do
    filter = [@prefix, msg.ident, "host", msg.name, msg.filter] |> Enum.join("/")
    %Reply{msg | filter: filter}
  end

  defp save_packed_length(%Reply{} = msg, length), do: %Reply{msg | packed_length: length}

  defp save_pub_rc(pub_rc, %Reply{} = msg) do
    case pub_rc do
      {:ok, ref} -> %Reply{msg | pub_ref: ref}
      _ -> msg
    end
  end

  defp set_qos(%Reply{} = msg), do: %Reply{msg | qos: msg.opts[:qos] || msg.qos}

  ##
  ## GenServer Reply Helpers
  ##

  # (1 of 2) handle plain %State{}
  defp noreply(%State{} = s), do: {:noreply, s}

  # (2 of 2) support pipeline {%State{}, msg} -- return State and discard message
  # defp noreply({%State{} = s, _msg}), do: {:noreply, s}

  # (1 of 4) handle pipeline: %State{} first, result second
  # defp reply(%State{} = s, res), do: {:reply, res, s}

  # (2 of 4) handle pipeline: result is first, %State{} is second
  # defp reply(res, %State{} = s), do: {:reply, res, s}

  # (3 of 4) assembles a reply based on a tuple (State, result) and rc
  # defp reply({%State{} = s, result}, rc), do: {:reply, {rc, result}, s}

  # (4 of 4) assembles a reply based on a tuple {State, result}
  defp reply({%State{} = s, result}), do: {:reply, result, s}

  defp reply_ok(%State{} = s) do
    Logger.debug(["\n", inspect(s, pretty: true), "\n"])

    {:ok, s}
  end
end
