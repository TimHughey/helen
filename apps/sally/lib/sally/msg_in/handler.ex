defmodule Sally.MsgIn.Handler do
  require Logger

  alias Sally.Types, as: Types

  @callback child_spec(Types.child_spec_opts()) :: Supervisor.child_spec()
  @callback handle_message(Sally.MsgIn.t()) :: any()

  defmacro __using__(use_opts) do
    # here we inject code into the using module so it can be started in a supervision tree
    # running an instance of Broom.Server
    quote location: :keep do
      require Sally.MsgIn.Handler
      alias Sally.MsgIn
      alias Sally.MsgIn.Handler
      alias Sally.MsgInFlight

      @behaviour Sally.MsgIn.Handler

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

  alias Sally.MsgIn.{Opts, Server}

  def make_child_spec(mod, use_opts, message_opts) do
    start_args = Opts.make_opts(mod, message_opts, use_opts)

    Supervisor.child_spec({Server, start_args}, id: start_args.server.id)
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
