defmodule Sally.Message.Handler do
  alias Sally.Types, as: Types

  @callback child_spec(Types.child_spec_opts()) :: Supervisor.child_spec()
  @callback process(struct()) :: struct()
  @callback post_process(struct()) :: struct()
  @callback finalize(struct()) :: struct()

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

  alias __MODULE__
  alias Sally.Types, as: Types

  defstruct server: %{id: nil, name: nil, genserver: []}, callback_mod: nil

  @type t :: %__MODULE__{server: Types.server_info_map(), callback_mod: Types.module_or_nil()}

  def make_opts(mod, _start_opts, use_opts) do
    log_final_opts = fn x ->
      Logger.debug(["final opts:\n", inspect(x, pretty: true)])
      x
    end

    {id, rest} = Keyword.pop(use_opts, :id, mod)
    {name, genserver_opts} = Keyword.pop(rest, :name, mod)

    %Opts{server: %{id: id, name: name, genserver: genserver_opts}, callback_mod: mod}
    |> log_final_opts.()
  end
end

defmodule Sally.Message.Handler.State do
  alias Sally.Message.Handler.Opts

  defstruct opts: %Opts{}

  @type t :: %__MODULE__{opts: Opts.t()}
end

defmodule Sally.Message.Handler.Server do
  require Logger
  use GenServer

  alias Sally.Message.Handler.{Opts, Server, State}

  @impl true
  def init(%Opts{} = opts) do
    %State{opts: opts} |> reply_ok()
  end

  def start_link(%Opts{} = opts) do
    # assemble the genserver opts
    genserver_opts = [name: opts.server.name] ++ opts.server.genserver
    GenServer.start_link(Server, opts, genserver_opts)
  end

  @impl true
  def handle_cast(%_{} = msg, %State{} = s) do
    %{msg | routed: :yes} |> s.opts.callback_mod.process()
    noreply(s)
  end

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

  # (4 of 4) assembles a reply based on a tuple {result, State}
  # defp reply({%State{} = s, result}), do: {:reply, result, s}

  defp reply_ok(%State{} = s) do
    Logger.debug(["\n", inspect(s, pretty: true), "\n"])

    {:ok, s}
  end
end
