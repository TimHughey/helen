defmodule Broom do
  defmacro __using__(use_opts) do
    # here we inject code into the using module so it can be started in a supervision tree
    # running an instance of Broom.Server
    quote location: :keep do
      require Broom

      alias Broom.TrackerEntry

      # (1 of 2) provided a Broom Opts struct, use it
      def child_spec(%{} = broom_opts) do
        Broom.make_child_spec(unquote(__CALLER__.module), unquote(use_opts), broom_opts)
      end

      # (2 of 2) use a default Broom Opts
      def child_spec(_), do: child_spec(%Broom.Opts{})
    end
  end

  ##
  ## Broom
  ##

  defmacro change_metrics_interval(new_interval) do
    quote location: :keep, bind_quoted: [mod: __CALLER__.module, new_interval: new_interval] do
      Broom.call({:change_metrics_interval, new_interval}, mod)
    end
  end

  defmacro counts do
    quote location: :keep, bind_quoted: [mod: __CALLER__.module] do
      Broom.call({:counts}, mod)
    end
  end

  def make_child_spec(mod, use_opts, broom_opts) do
    alias Broom.Opts

    start_args = Opts.make_opts(mod, broom_opts, use_opts)

    Supervisor.child_spec({Broom.Server, start_args}, id: start_args.server.id)
  end

  defmacro release(what) do
    quote location: :keep do
      Broom.Release.db_result(unquote(__CALLER__.module), unquote(what))
    end
  end

  defmacro track(what, opts) do
    quote location: :keep do
      Broom.Track.db_result(unquote(__CALLER__.module), unquote(what), unquote(opts))
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
