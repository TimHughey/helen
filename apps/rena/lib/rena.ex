defmodule Rena do
  @moduledoc """
  Documentation for `Rena`.
  """

  defmacro __using__(use_opts) do
    quote bind_quoted: [use_opts: use_opts] do
      @behaviour Rena

      @use_opts Enum.into(use_opts, %{})

      def child_spec(opts), do: Rena.child_spec(__MODULE__, opts, @use_opts)
    end
  end

  @callback child_spec(list) :: map

  require Logger
  use GenServer
  use Alfred, name: [backend: :message], execute: []

  @opts_error "ambiguous start and use opts: "
  def child_spec(module, opts, %{} = use_opts) when map_size(use_opts) > 0 do
    {otp_app, use_opts} = Map.pop(use_opts, :otp_app)
    restart = Map.get(use_opts, :restart, :permanent)

    case {otp_app, use_opts} do
      {otp_app, use_opts} when is_nil(otp_app) and map_size(use_opts) > 2 -> Enum.into(use_opts, [])
      {otp_app, _} when is_atom(otp_app) -> Application.get_env(otp_app, module)
      _ -> raise(@opts_error <> inspect({{:opts, opts}, {:use_opts, use_opts}}))
    end
    |> Keyword.put_new(:restart, restart)
    |> then(fn opts -> child_spec(module, opts, %{}) end)
  end

  def child_spec(module, opts, _use_opts) when is_atom(module) do
    unless is_list(opts) and opts != [], do: raise("must supply opts")

    {restart, opts} = Keyword.pop(opts, :restart, :permanent)

    opts_final = [server_name: module] ++ opts

    # build the final child_spec map
    %{id: module, start: {__MODULE__, :start_link, [opts_final]}, restart: restart}
  end

  defstruct server_name: nil,
            name: nil,
            nature: :server,
            equipment: nil,
            register: nil,
            sensor: %Rena.Sensor{},
            seen_at: nil,
            status: %{},
            ticket: :none,
            ttl_ms: 60_000

  @type cmds :: [{:active, list()}, {:inactive, list()}]
  @type ticket() :: :none | :paused | Alfred.Ticket.t()
  @type t :: %__MODULE__{
          server_name: atom(),
          name: String.t(),
          nature: :server,
          equipment: String.t(),
          register: nil | pid,
          sensor: Rena.Sensor.t(),
          seen_at: nil | %DateTime{},
          status: map(),
          ticket: ticket(),
          ttl_ms: pos_integer()
        }

  @impl true
  def init(args) do
    state = make_state(args)

    {:ok, state, {:continue, :bootstrap}}
  end

  def start_link(start_args) do
    server_opts = [name: start_args[:server_name]]
    GenServer.start_link(__MODULE__, start_args, server_opts)
  end

  @impl true
  def handle_call({:execute_cmd, [_name_info, opts]}, _from, state) do
    {rc, {result, new_state}} = execute_cmd(state, opts)

    # NOTE: invoke tick to handle any changes made by the cmd
    {:reply, {rc, result}, new_state, {:continue, :tick}}
  end

  @impl true
  def handle_call({:status_lookup, [_name_info, opts]}, _from, state) do
    status_lookup = status_lookup(state, opts)

    reply(status_lookup, state)
  end

  @impl true

  def handle_continue(:bootstrap, state) do
    start_notifies(state) |> noreply()

    # NOTE: at this point the server is running and no further actions occur until an
    #       equipment notification is received
  end

  @impl true
  def handle_continue(:tick, %{equipment: equipment, sensor: sensor} = state) do
    state = struct(state, seen_at: opts(:timezone) |> Timex.now())

    sensor = Rena.Sensor.freshen(sensor, equipment, opts())

    case sensor do
      %{halt_reason: <<_::binary>> = reason} ->
        _ = Betty.app_error_v2(state, name: state.name)
        Logger.warn(reason)

      %{next_action: {:no_change, :none}} ->
        nil

      %{next_action: {:no_match, _cmd} = next_action} ->
        inspect(next_action) |> Logger.warn()

      %{next_action: {action, cmd}} ->
        alfred = opts(:alfred)
        alfred.execute(name: equipment, cmd: cmd, notify: false)

        _ = Betty.runtime_metric(state, [name: state.name, cmd: cmd], [{action, true}])
    end

    struct(state, sensor: sensor)
    |> register()
    |> noreply()
  end

  # NOTE: missing: true messages are not sent by default, no need to handle them
  @impl true
  def handle_info({Alfred, %Alfred.Memo{}}, state) do
    {:noreply, state, {:continue, :tick}}
  end

  @impl true
  def handle_info(:restart, state), do: {:stop, :normal, state}

  # Alfred Callbacks
  @impl true
  def execute_cmd(state, opts) do
    alfred = opts(:alfred)
    opts_map = Enum.into(opts, %{})

    case opts_map do
      %{cmd: "pause" = cmd} ->
        state = alfred.notify_unregister(state)
        {:ok, {%{cmd: cmd, sent_at: state.seen_at}, state}}

      %{cmd: "restart" = cmd} ->
        _ = Process.send_after(self(), :restart, 0)
        {:ok, {%{cmd: cmd, sent_at: state.seen_at}, state}}

      %{cmd: "resume" = cmd} ->
        state = start_notifies(state)
        {:ok, {%{cmd: cmd, sent_at: state.seen_at}, state}}

      _ ->
        {:error, {%{}, state}}
    end
  end

  @impl true
  def status_lookup(%{} = state, _opts) do
    base = Map.take(state, [:name, :seen_at, :ttl_ms])

    status = %{
      sensor: state.sensor,
      equipment: Alfred.status(state.equipment, binary: true),
      notify: if(match?({:ok, %{}}, state.ticket), do: "enabled", else: "disabled")
    }

    Map.put(base, :status, status)
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  @common [:alfred, :id, :opts]
  @name_error "must specify :name to register"
  @want_fields [:alfred, :server_name, :equipment, :name, :timezone]
  def make_state(args) do
    {common_opts, args_rest} = Keyword.split(args, @common)

    opts = opts_store(common_opts)

    {base_fields, args_rest} = Keyword.split(args_rest, @want_fields)
    {sensor_opts, args_rest} = Keyword.pop(args_rest, :sensor_group)
    {_dev_alias, args_rest} = Keyword.pop(args_rest, :dev_alias)

    unless match?(<<_::binary>>, base_fields[:name]), do: raise(@name_error)
    unless args_rest == [], do: Logger.warn(["extra fields: ", inspect(args_rest)])

    sensor = Rena.Sensor.new(sensor_opts)
    fields = [server_name: opts[:server_name], sensor: sensor] ++ base_fields

    struct(__MODULE__, fields)
  end

  def opts(keys \\ []) do
    opts = Process.get(:opts)

    case keys do
      key when is_atom(key) -> get_in(opts, [key])
      [_ | _] -> Keyword.take(opts, keys)
      _ -> opts
    end
  end

  def opts_store(common_opts) do
    {opts, rest} = Keyword.pop(common_opts, :opts, [])

    Keyword.merge(rest, opts)
    |> Keyword.put_new(:alfred, Alfred)
    |> tap(fn opts_all -> Process.put(:opts, opts_all) end)
  end

  @notify_opts [interval_ms: 30_000, missing_ms: 60_000, send_missing_msg: false]
  def start_notifies(%{} = state) do
    alfred = opts(:alfred)
    alfred.notify_register(state, @notify_opts)
  end

  def noreply(%{} = state) do
    reply = {:noreply, state}

    if opts(:echo) == :tick, do: Process.send(opts(:caller), reply, [])

    reply
  end

  def reply(rc, %Rena{} = state), do: {:reply, rc, state}
end
