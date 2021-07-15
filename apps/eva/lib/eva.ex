defmodule Eva do
  use Timex

  @type eva_child_spec_opts() :: map() | keyword()
  @callback child_spec(eva_child_spec_opts()) :: Supervisor.child_spec()
  @callback kill() :: pid()

  defmacro __using__(use_opts) do
    # here we inject code into the using module so it can be started in a supervision tree
    # running an instance of Eva.Server
    quote location: :keep do
      require Eva
      @behaviour Eva

      def child_spec(eva_opts) do
        Eva.make_child_spec(unquote(__CALLER__.module), unquote(use_opts), eva_opts)
      end

      def current_mode, do: Eva.current_mode(unquote(__CALLER__.module))
      def equipment, do: Eva.equipment(unquote(__CALLER__.module))
      def kill, do: Eva.kill(unquote(__CALLER__.module))
      def resume, do: Eva.resume(unquote(__CALLER__.module))
      def standby, do: Eva.standby(unquote(__CALLER__.module))
      def state, do: Eva.state(unquote(__CALLER__.module))
    end
  end

  ##
  ## Eva
  ##

  def current_mode(mod) do
    GenServer.call(mod, :current_mode)
  rescue
    _ -> :no_server
  end

  def equipment(mod) do
    GenServer.call(mod, :equipment)
  rescue
    _ -> :no_server
  end

  def kill(mod) do
    GenServer.whereis(mod) |> Process.exit(:kill)
  rescue
    _ -> :error
  else
    true -> GenServer.whereis(mod)
    error -> error
  end

  def make_child_spec(mod, use_opts, eva_opts) do
    alias Eva.{Opts, Server}

    start_args = Opts.make_opts(mod, eva_opts, use_opts)

    Supervisor.child_spec({Server, start_args}, id: start_args.server.id)
  end

  def parse_duration(binary) do
    Duration.parse!(binary) |> Duration.to_milliseconds(truncate: true)
  rescue
    _ -> nil
  end

  def resume(mod) do
    GenServer.call(mod, :resume)
  rescue
    _ -> :no_server
  end

  def standby(mod) do
    GenServer.call(mod, :standby)
  rescue
    _ -> :no_server
  end

  def state(mod) do
    GenServer.whereis(mod) |> :sys.get_state()
  rescue
    _ -> :no_server
  end
end
