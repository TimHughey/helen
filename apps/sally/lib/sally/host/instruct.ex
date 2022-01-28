defmodule Sally.Host.Instruct do
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
  alias Sally.Host.Instruct.State

  @client_id Application.compile_env!(:sally, [:mqtt_connection, :client_id])
  @qos_default 0
  @prefix Application.compile_env!(:sally, [Instruct, :publish, :prefix])

  defstruct client_id: @client_id,
            ident: nil,
            name: nil,
            subsystem: "host",
            mtime: :populate_when_sent,
            data: %{},
            filters: [],
            opts: [],
            packed_length: 0,
            pub_ref: nil,
            qos: @qos_default

  ##
  ## Public API
  ##

  def echo_if_requested(%__MODULE__{opts: opts} = instruct, caller_pid) do
    case opts do
      %{echo: :instruct} -> Process.send(caller_pid, instruct, [])
      _ -> :ok
    end

    instruct
  end

  def send(%Instruct{} = msg) do
    {:send, msg |> add_mtime() |> set_qos()}
    |> Instruct.call()
  end

  def send(%{} = fields), do: Enum.into(fields, []) |> send()

  def send([_ | _] = fields) do
    opts = Keyword.get(fields, :opts, []) |> Enum.into(%{})

    fields
    |> Keyword.put(:opts, Enum.into(opts, %{}))
    |> then(fn fields -> struct(__MODULE__, fields) end)
    |> send()
  end

  @impl true
  def init(_) do
    %State{} |> reply_ok()
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def handle_call({:send, %Instruct{} = msg}, {caller_pid, _term}, %State{} = s) do
    packed = Map.put(msg.data, :mtime, msg.mtime) |> Msgpax.pack!()

    Tortoise.publish(msg.client_id, make_filter(msg), packed, qos: msg.qos, timeout: 200)
    |> save_pub_rc(msg)
    |> save_packed_length(IO.iodata_length(packed))
    |> echo_if_requested(caller_pid)
    |> State.save_last_pub(s)
    |> reply()
  end

  @impl true
  def handle_info({{Tortoise, _client_id}, _ref, res}, %State{} = s) do
    res |> tap(fn x -> ["\n", inspect(x, pretty: true)] |> IO.warn() end)
    s |> noreply()
  end

  ##
  ## GenServer Call / Cast Helpers
  ##

  @doc false
  def call(msg) when is_tuple(msg) do
    case GenServer.whereis(Instruct) do
      x when is_pid(x) -> GenServer.call(x, msg)
      x -> {:no_server, x}
    end
  end

  defp add_mtime(%Instruct{} = msg), do: %Instruct{msg | mtime: System.os_time(:millisecond)}

  defp make_filter(%Instruct{} = msg) do
    ([@prefix, "c2", msg.ident, msg.subsystem] ++ msg.filters) |> Enum.join("/")
  end

  defp save_packed_length(%Instruct{} = msg, length), do: %Instruct{msg | packed_length: length}

  defp save_pub_rc(pub_rc, %Instruct{} = msg) do
    case pub_rc do
      {:ok, ref} -> %Instruct{msg | pub_ref: ref}
      _ -> msg
    end
  end

  defp set_qos(%Instruct{} = msg), do: %Instruct{msg | qos: msg.opts[:qos] || msg.qos}

  ##
  ## GenServer Instruct Helpers
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
