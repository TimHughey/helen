defmodule Sally.MsgOut.Client do
  alias Sally.Message.Types, as: Types

  @callback child_spec(Types.child_spec_opts()) :: Supervisor.child_spec()
  @callback publish(Types.pub_topic_filters(), Types.pub_data(), Types.pub_opts()) :: Types.pub_rc()

  defmacro __using__(use_opts) do
    # here we inject code into the using module so it can be started in a supervision tree
    # running an instance of Broom.Server
    quote location: :keep do
      require Sally.MsgOut.Client
      alias Sally.MsgOut

      @behaviour MsgOut.Client

      @doc false
      @impl true
      def child_spec(start_opts) do
        MsgOut.Client.make_child_spec(unquote(__CALLER__.module), start_opts, unquote(use_opts))
      end

      @impl true
      def publish(filters, data, pub_opts) do
        MsgOut.create(filters, data, pub_opts) |> MsgOut.Client.publish()
      end
    end
  end

  ##
  ## MsgOut Client
  ##

  # alias Sally.MsgOut
  alias Sally.MsgOut.{Client, Opts, Server}

  def make_child_spec(mod, use_opts, start_opts) do
    opts = Opts.make_opts(mod, start_opts, use_opts)

    Supervisor.child_spec({Server, opts}, id: opts.server.id)
  end

  defmacro publish(mo) do
    quote bind_quoted: [mod: __CALLER__.module, mo: mo] do
      {:publish, mo} |> Client.call(mod)
    end
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
