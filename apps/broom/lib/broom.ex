defmodule Broom do
  require Logger

  defmacro __using__(use_opts) do
    # here we inject code into the using module so it can be started in a supervision tree
    # running an instance of Broom.Server
    quote location: :keep do
      require Broom
      @behaviour Broom.Behaviour

      alias Broom.TrackerEntry

      def child_spec(broom_opts) do
        Broom.make_child_spec(unquote(__CALLER__.module), unquote(use_opts), broom_opts)
      end
    end
  end

  ##
  ## Broom
  ##

  defmacro change_metrics_interval(new_interval) do
    quote bind_quoted: [mod: __CALLER__.module, new_interval: new_interval] do
      Broom.via_mod_change_metrics_interval(mod, new_interval)
    end
  end

  defmacro counts do
    quote bind_quoted: [mod: __CALLER__.module] do
      Broom.via_mod_counts(mod)
    end
  end

  defmacro counts_reset(opts) do
    quote bind_quoted: [mod: __CALLER__.module, opts: opts] do
      Broom.via_mod_counts_reset(mod, opts)
    end
  end

  defmacro get_refid_tracker_entry(refid) do
    quote bind_quoted: [mod: __CALLER__.module, refid: refid] do
      Broom.via_mod_get_refid_tracker_entry(mod, refid)
    end
  end

  def make_child_spec(mod, use_opts, broom_opts) do
    alias Broom.Opts

    start_args = Opts.make_opts(mod, broom_opts, use_opts)

    Supervisor.child_spec({Broom.Server, start_args}, id: start_args.server.id)
  end

  defmacro release(db_result_or_refid) do
    quote bind_quoted: [mod: __CALLER__.module, db_result_or_refid: db_result_or_refid] do
      Broom.via_mod_release(mod, db_result_or_refid)
    end
  end

  defmacro track(what, opts) do
    quote bind_quoted: [mod: __CALLER__.module, what: what, opts: opts] do
      Broom.via_mod_track(mod, what, opts)
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

  ##
  ## function invocation using a passed module
  ##

  @doc false
  def via_mod_get_refid_tracker_entry(mod, refid) do
    {:get_refid_entry, refid} |> Broom.call(mod)
  end

  @doc false
  def via_mod_change_metrics_interval(mod, new_interval) do
    {:change_metrics_interval, new_interval} |> Broom.call(mod)
  end

  @doc false
  def via_mod_counts(mod) do
    {:counts} |> Broom.call(mod)
  end

  @doc false
  def via_mod_counts_reset(mod, opts) do
    {:counts_reset, opts} |> Broom.call(mod)
  end

  @doc false
  def via_mod_release(mod, db_result_or_refid) do
    {:release, db_result_or_refid} |> Broom.call(mod)
  end

  @doc false
  def via_mod_track(mod, what, opts) do
    Broom.Track.db_result(mod, what, opts)
  end
end
