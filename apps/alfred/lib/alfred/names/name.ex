defmodule Alfred.Name do
  @moduledoc false

  require Logger
  use GenServer

  @registry Alfred.Application.registry(:name)
  @callback_default {__MODULE__, :callback_default}
  @callback_defaults %{status: @callback_default, execute: @callback_default}
  @nature_default :datapoints
  @natures [:cmds, :datapoints]

  defstruct name: nil, nature: @nature_default, seen_at: nil, ttl_ms: 30_000, callbacks: @callback_defaults

  @doc since: "0.3.0"
  def allowed_opts, do: [:seen_at, :ttl_ms, :callbacks]

  @impl true
  def init(fields) do
    {from, fields_rest} = Keyword.pop(fields, :from)

    Process.link(from)

    {:ok, struct(__MODULE__, fields_rest)}
  end

  def start_link(opts) when is_list(opts) do
    {via_name, opts_rest} = Keyword.pop(opts, :name)
    {seen_at, opts_rest} = Keyword.pop(opts_rest, :seen_at, DateTime.utc_now())
    {natures, opts_rest} = Keyword.split(opts_rest, @natures)
    {fields_base, _} = Keyword.split(opts_rest, [:name, :ttl_ms, :callbacks])

    [
      name: short_name(via_name),
      nature:
        Enum.reduce_while(natures, @nature_default, fn
          {_key, val}, acc when is_nil(val) or val == false -> {:cont, acc}
          {key, _val_}, _acc -> {:halt, key}
        end),
      from: self(),
      seen_at: seen_at
    ]
    |> then(fn fields_extra -> Keyword.merge(fields_base, fields_extra) end)
    |> then(fn fields -> GenServer.start_link(__MODULE__, fields, name: via_name, restart: :temporary) end)
  end

  def start_link(opts) when is_struct(opts) or is_map(opts) do
    case opts do
      x when is_struct(x) -> Map.from_struct(x) |> Enum.into([])
      x when is_map(x) -> Enum.into(x, [])
    end
    |> start_link()
  end

  def callback(name, what) when is_binary(name) and what in [:execute, :status] do
    case callbacks(name) do
      %{^what => callback} -> callback
      not_found -> not_found
    end
  end

  def callbacks(name) when is_binary(name), do: call({:get, :callbacks}, name)

  def info(<<_::binary>> = name), do: call({:info}, name)

  def missing?(any, opts) when is_list(opts) do
    case any do
      <<_::binary>> = name -> call({:missing?, opts}, name)
      %{name: name} -> call({:missing?, opts}, name)
      _ -> {:failed, :bad_args}
    end
  end

  # (1 of 2)
  def register(any, opts \\ [])

  def register(<<_::binary>> = name, opts) when is_list(opts) do
    case call({:register, opts}, name) do
      {:not_found, _} -> start_link([name: server(name)] ++ opts)
      result -> result
    end
  end

  # (2 of 3) register a binary name using opts
  def register(any, opts) when is_list(opts) do
    case any do
      {<<_::binary>> = name, opts} -> register(name, opts)
      x when is_struct(x) -> Map.from_struct(x) |> register(opts)
      x when is_map(x) -> register_opts_from_map(x, opts) |> register()
      _ -> {:failed, :bad_args}
    end
  end

  def seen_at(%{name: name}), do: seen_at(name)

  # (2 of 2)
  def seen_at(name) when is_binary(name), do: call({:get, :seen_at}, name)

  def unregister(name) when is_binary(name) do
    case Registry.lookup(@registry, name) do
      [{pid, _}] -> GenServer.stop(pid, :normal)
      [] -> :ok
    end
  end

  ## GenServer

  @impl true
  def handle_call({:get, key}, _from, state) when is_map_key(state, key) do
    Map.get(state, key) |> reply(state)
  end

  @impl true
  def handle_call({:info}, _from, state) do
    Map.from_struct(state) |> reply(state)
  end

  @impl true
  def handle_call({:missing?, opts}, _from, state) do
    at = opts[:ref_dt] || DateTime.utc_now()
    ttl_ms = opts[:ttl_ms] || state.ttl_ms

    diff_greater_than_ms?(at, state.seen_at, ttl_ms)
    |> reply(state)
  end

  @impl true
  def handle_call({:register, opts}, _from, state) do
    at = opts[:ref_dt] || DateTime.utc_now()

    struct(state, seen_at: at)
    |> tap(fn state -> Alfred.Notify.dispatch(state, opts) end)
    |> reply(:ok)
  end

  @impl true
  def handle_call(msg, _from, state), do: {:invalid_msg, msg} |> reply(state)

  @impl true
  def terminate(reason, %{name: name} = state) do
    reason = inspect(reason)
    pid = inspect(self())
    ["\n", "  ", name, " ", pid, " terminating ", reason] |> Logger.debug()

    state
  end

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  @doc false
  def callback_default(_what, _opts), do: {:failed, :default_callback}

  @doc false
  def diff_greater_than_ms?(lhs, rhs, ms), do: Timex.diff(lhs, rhs, :milliseconds) >= ms

  @doc false
  def server(name), do: {:via, Registry, {@registry, name}}

  @doc false
  def short_name({:via, Registry, {_, short_name}}), do: short_name

  ## PRIVATE
  ## PRIVATE
  ## PRIVATE

  defmacrop format_exception(kind, reason) do
    quote do
      ["\n", Exception.format(unquote(kind), unquote(reason), __STACKTRACE__)] |> IO.puts()

      {:failed, {unquote(kind), unquote(reason)}}
    end
  end

  defp call(msg, name) do
    server(name) |> GenServer.call(msg)
  catch
    _kind, {:noproc, {GenServer, :call, _}} -> {:not_found, name}
    kind, reason -> format_exception(kind, reason)
  end

  @map_opts [:updated_at, :seen_at]
  @take_opts [:cmds, :datapoints, :ttl_ms]
  defp register_opts_from_map(%{name: name} = map, opts) do
    {
      name,
      # NOTE: combination of take and map
      Enum.reduce(map, opts, fn kv, acc ->
        case kv do
          {key, val} when key in @map_opts -> Keyword.put_new(acc, :seen_at, val)
          {key, val} when key in @take_opts -> Keyword.put_new(acc, key, val)
          _ -> acc
        end
      end)
    }
  end

  defp reply(rc, %__MODULE__{} = state), do: {:reply, rc, state}
  defp reply(%__MODULE__{} = state, rc), do: {:reply, rc, state}
end
