defmodule Alfred.Execute do
  @moduledoc """
  Generalized execute of an `Alfred.Name`

  """

  @rc_default {:unset, :default}

  defstruct name: :none, detail: :none, rc: @rc_default

  @callback execute_cmd(any(), opts :: list()) :: any()
  @callback execute(args :: any(), opts :: list) :: any()

  defmacrop continue(val) do
    %{function: {what, _}} = __CALLER__

    quote bind_quoted: [val: val, what: what] do
      {:cont, Map.put(var!(checks_map), what, val)}
    end
  end

  defmacrop halt(rc, detail) do
    %{function: {what, _}} = __CALLER__

    quote bind_quoted: [rc: rc, detail: detail, what: what] do
      checks_map = var!(checks_map)
      detail = if(detail == :none, do: :none, else: Map.get(checks_map, :detail, %{}) |> Map.merge(detail))

      {:halt, Map.merge(checks_map, %{what => rc, rc: rc, detail: detail})}
    end
  end

  # Executing a command for a Name
  #
  #

  @doc since: "0.3.0"

  # (aaa of bbb) accept a tuple of args and overrides
  def execute({[_ | _] = args, overrides}) when is_list(overrides) do
    Alfred.Execute.Args.auto({args, overrides}) |> Enum.into(%{}) |> execute()
  end

  def execute(%{name: name} = args_map) do
    info = Alfred.Name.info(name)
    args_all = [{:__name_info__, info} | Enum.into(args_map, [])]

    case info do
      %{callbacks: %{execute: {mod, _}, status: {_, _}}} -> mod.execute(name, args_all)
      %{callbacks: %{execute: nil}} -> struct(__MODULE__, name: name, rc: :not_supported)
      {:not_found = rc, name} -> struct(__MODULE__, name: name, rc: rc)
      rc -> rc
    end
  end

  @checks [:registered, :ttl_info, :status, :verify, :compare, :execute_cmd, :track, :finalize]
  def execute(args, module) when is_list(args) and is_atom(module) do
    name = Keyword.get(args, :name)
    {info, args_rest} = Keyword.pop(args, :__name_info__, Alfred.Name.info(name))
    opts = Keyword.merge([ref_dt: Timex.now()], args_rest)

    overrides = overrides_map(module)

    checks_map = %{
      info: info,
      name: name,
      force: if(get_in(opts, [:cmd_opts, :force]) == true, do: true, else: false),
      broom_module: broom_module(module)
    }

    Enum.reduce_while(@checks, checks_map, fn
      what, checks_map when is_map_key(overrides, what) -> module.check(what, checks_map, opts)
      :registered, %{info: %{name: _}} -> continue(:ok)
      :registered, %{info: {:not_found = rc, _name}} -> halt(rc, :none)
      :ttl_info, checks_map -> ttl_info(checks_map, opts)
      :status, checks_map -> status(checks_map, opts)
      :verify, checks_map -> verify(checks_map)
      :compare, checks_map -> compare(checks_map, opts)
      :execute_cmd, checks_map -> execute_cmd(checks_map, opts)
      :track, checks_map -> track(checks_map, opts)
      :finalize, checks_map -> finalize(checks_map)
    end)
    |> new_from_checks_accumulator()
  end

  def execute([_ | _] = args, opts) when is_list(opts) do
    Alfred.Execute.Args.auto({args, opts}) |> Enum.into(%{}) |> execute()
  end

  @doc since: "0.3.0"
  def off(name, opts), do: execute([name: name, cmd: "off"], opts)

  @doc since: "0.3.0"
  def on(name, opts), do: execute([name: name, cmd: "on"], opts)

  @doc since: "0.3.0"
  def toggle(_name, _opts) do
    :ok
  end

  @doc """
  Convert an `Alfred.Execute` to a sratus binary

  """
  @doc since: "0.3.0"
  def to_binary(%{name: name} = execute, _opts \\ []) do
    case execute do
      %{rc: :ok, detail: %{cmd: cmd}} -> ["OK", "{#{cmd}}"]
      %{rc: :busy, detail: %{cmd: cmd, refid: refid}} -> ["BUSY", "{#{cmd}}", "@#{refid}"]
      %{rc: :not_found} -> ["NOT_FOUND"]
      %{rc: {:ttl_expired, ms}} -> ["TTL_EXPIRED", "+#{ms}ms"]
      %{rc: {:orphaned, ms}} -> ["ORPHANED", "+#{ms}ms"]
      %{rc: :error} -> ["ERROR"]
      _ -> ["UNMATCHED"]
    end
    |> then(fn detail -> detail ++ ["[#{name}]"] end)
    |> Enum.join(" ")
  end

  ##
  ## END OF PUBLIC API
  ##

  @doc false
  def compare(%{status: status, force: force} = checks_map, opts) do
    want_cmd = opts[:cmd]

    case status do
      _status when force -> continue(:force)
      %{detail: %{rc: rc} = detail} when rc in [:busy, :error] -> halt(rc, detail)
      %{detail: %{cmd: ^want_cmd} = detail} -> halt(:ok, detail)
      _ -> continue(:not_equal)
    end
  end

  @doc false
  def execute_cmd(checks_map, opts) do
    %{status: status, info: %{callbacks: %{execute: {module, 2}}}} = checks_map

    case module.execute_cmd(status, opts) do
      {rc, result} when rc in [:ok, :busy] -> continue({rc, result})
      {rc, result} -> halt(rc, result)
    end
  end

  @doc false
  def status(%{info: info} = checks_map, opts) do
    %{callbacks: %{status: {module, 2}}} = info

    module.status(info.name, opts) |> continue()
  end

  @doc false
  def finalize(checks_map) do
    %{execute_cmd: {rc, exec_result}, track: track_result} = checks_map

    detail = %{cmd: exec_result.cmd, __execute__: exec_result, __track__: track_result}

    halt(rc, detail)
  end

  @doc false
  def new_from_checks_accumulator({:cont, checks_map}) do
    new_from_checks_accumulator(checks_map)
  end

  def new_from_checks_accumulator(checks_map) do
    checks_map
    |> Map.take([:detail, :name, :rc])
    |> Map.put_new(:detail, :none)
    |> then(fn fields -> struct(__MODULE__, fields) end)
  end

  @doc false
  def ttl_info(%{info: info} = checks_map, opts) do
    %{ttl_ms: ttl_ms, seen_at: at} = info

    ref_dt = Keyword.get(opts, :ref_dt)
    ttl_ms = Keyword.get(opts, :ttl_ms, ttl_ms)

    ttl_start_at = Timex.shift(ref_dt, milliseconds: ttl_ms * -1)

    # if either the device hasn't been seen or the DevAlias hasn't been updated then the ttl is expired
    if Timex.before?(ttl_start_at, at) do
      continue(:ok)
    else
      halt({:ttl_expired, DateTime.diff(ref_dt, at, :millisecond)}, :none)
    end
  end

  @doc false
  def track(checks_map, opts) do
    case checks_map do
      %{broom_module: :none = rc} -> rc
      %{broom_module: module, execute_cmd: {:busy, cmd}} -> module.track(cmd, opts)
      _ -> :ok
    end
    |> continue()
  end

  @doc false
  def verify(%{status: status} = checks_map) do
    case status do
      %Alfred.Status{rc: :ok} -> continue(:ok)
      %Alfred.Status{rc: rc, detail: detail} -> halt(rc, detail)
    end
  end

  ##
  ## __using__ and helpers
  ##

  @mod_attribute :alfred_execute_use_opts

  # coveralls-ignore-start
  @doc false
  defmacro __using__(use_opts) do
    quote bind_quoted: [use_opts: use_opts] do
      Alfred.Execute.put_attribute(__MODULE__, use_opts)

      @behaviour Alfred.Execute
      def execute({[_ | _] = _args, opts} = tuple) when is_list(opts) do
        tuple |> Alfred.Execute.Args.auto() |> Alfred.Execute.execute(__MODULE__)
      end

      def execute(<<_::binary>> = name, opts) do
        Keyword.put(opts, :name, name)
        |> Alfred.Execute.execute(__MODULE__)
      end

      def execute(args, opts) when is_list(opts) do
        Alfred.Execute.Args.auto({args, opts}) |> Alfred.Execute.execute(__MODULE__)
      end
    end
  end

  @doc false
  @broom_key [@mod_attribute, :broom]
  def broom_module(module), do: module.__info__(:attributes) |> get_in(@broom_key)

  @doc false
  def put_attribute(module, use_opts) do
    Module.register_attribute(module, @mod_attribute, persist: true)
    overrides = use_opts[:overrides] || []

    # broom = use_opts[:broom]
    #
    # unless Module.open?(broom) do
    #   mod_funcs = broom.__info__(:functions)
    # end

    [
      broom: use_opts[:broom] || :none,
      overrides: Enum.into(overrides, %{}, fn key -> {key, true} end)
    ]
    |> then(fn val -> Module.put_attribute(module, @mod_attribute, val) end)
  end

  # coveralls-ignore-stop

  @doc false
  def overrides_map(module) do
    get_in(module.__info__(:attributes), [@mod_attribute, :overrides])
  end
end
