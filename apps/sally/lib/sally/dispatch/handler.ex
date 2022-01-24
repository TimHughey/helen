defmodule Sally.Message.Handler do
  @moduledoc false
  alias Sally.Types, as: Types

  @callback child_spec(Types.child_spec_opts()) :: Supervisor.child_spec()
  @callback process(struct()) :: struct()
  @callback post_process(struct()) :: struct()
  @optional_callbacks post_process: 1
  # @callback finalize(struct()) :: struct()

  defmacro __using__(use_opts) do
    # here we inject code into the using module so it can be started in a supervision tree
    # running an instance of Message.Handler.Server
    quote location: :keep do
      require Sally.Message.Handler
      alias Sally.Message.Handler

      @behaviour Sally.Message.Handler

      @doc false
      @impl true
      def child_spec(message_opts) do
        Handler.make_child_spec(unquote(__CALLER__.module), unquote(use_opts), message_opts)
      end
    end
  end

  ##
  ## Message
  ##

  alias Sally.Message.Handler

  def make_child_spec(mod, use_opts, message_opts) do
    start_args = Handler.Opts.make_opts(mod, message_opts, use_opts)

    Supervisor.child_spec({Handler.Server, start_args}, id: start_args.server.id)
  end

  ##
  ## GenServer Call / Cast Helpers
  ##

  @doc false
  def call(msg, mod) when is_tuple(msg) and is_atom(mod) do
    case GenServer.whereis(mod) do
      x when is_pid(x) -> GenServer.call(x, msg)
      _ -> {:no_server, mod}
    end
  end

  @doc false
  def cast(msg, mod) when is_tuple(msg) and is_atom(mod) do
    # returns:
    # 1. {:ok, original msg}
    # 2. {:no_server, original_msg}
    case GenServer.whereis(mod) do
      x when is_pid(x) -> {GenServer.cast(x, msg), msg}
      _ -> {:no_server, mod}
    end
  end
end

defmodule Sally.Message.Handler.Opts do
  require Logger

  defstruct server: %{id: nil, name: nil, genserver: []}, callback_mod: nil

  @type t :: %__MODULE__{server: Sally.Types.server_info_map(), callback_mod: Sally.Types.module_or_nil()}

  def make_opts(mod, _start_opts, use_opts) do
    {id, rest} = Keyword.pop(use_opts, :id, mod)
    {name, genserver_opts} = Keyword.pop(rest, :name, mod)

    [server: %{id: id, name: name, genserver: genserver_opts}, callback_mod: mod]
    |> then(fn fields -> struct(__MODULE__, fields) end)
  end

  def server_opts(%__MODULE__{server: %{genserver: genserver_opts, name: name}}) do
    Keyword.put_new(genserver_opts, :name, name)
  end
end

defmodule Sally.Message.Handler.Server do
  @moduledoc false

  require Logger
  use GenServer

  @impl true
  def init(%{} = opts), do: {:ok, _state = %{opts: opts}}

  def start_link(opts) do
    # assemble the genserver opts
    Sally.Message.Handler.Opts.server_opts(opts)
    |> then(fn server_opts -> GenServer.start_link(__MODULE__, opts, server_opts) end)
  end

  @impl true
  def handle_call(%Sally.Dispatch{} = dispatch, {caller_pid, _ref}, state) do
    # NOTE: reply quickly to free up MQTT handler, do the heavy lifting in the server
    {:reply, :ok, state, {:continue, {dispatch, caller_pid}}}
  end

  @impl true
  def handle_cast(%Sally.Dispatch{} = dispatch, state) do
    %{opts: %{callback_mod: callback_mod}} = state

    # NOTE: return value ignored, pure side effects function
    _ = process(dispatch, callback_mod)

    {:noreply, state}
  end

  @impl true
  def handle_continue({%{opts: opts} = dispatch, caller_pid}, state) do
    %{opts: %{callback_mod: callback_mod}} = state

    dispatch = process(dispatch, callback_mod)

    if opts[:echo] == "dispatch", do: Process.send(caller_pid, dispatch, [])

    {:noreply, state}
  end

  ##
  ## Private
  ##

  @order [:routed, :process, :check_txn, :post_process, :finalize, :finished]
  def process(%Sally.Dispatch{} = dispatch, callback_mod) do
    Enum.reduce_while(@order, dispatch, fn
      _function, %{valid?: false} = dispatch -> {:halt, Sally.Dispatch.finalize(dispatch)}
      _function, %{halt_reason: <<_::binary>>} -> {:halt, Sally.Dispatch.finalize(dispatch)}
      :finished, dispatch -> {:halt, dispatch}
      :routed, dispatch -> {:cont, Sally.Dispatch.routed(dispatch, callback_mod)}
      function, dispatch -> {:cont, apply(Sally.Dispatch, function, [dispatch])}
    end)
  end
end
