defmodule Alfred.Execute do
  @moduledoc """
  Generalized execute of an `Alfred.Name`

  """

  @rc_default {:unset, :default}

  defstruct name: :none, detail: :none, rc: @rc_default

  @callback execute_cmd(any(), opts :: list()) :: any()
  @callback execute(args :: any(), opts :: list) :: any()

  # Executing a command for a Name
  #
  #

  @doc since: "0.3.0"
  @checks [:registered, :ttl_info, :status, :verify, :compare, :execute, :track, :finalize]
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

  def execute(args, module) when is_list(args) and is_atom(module) do
    name = Keyword.get(args, :name)
    {info, args_rest} = Keyword.pop(args, :__name_info__, Alfred.Name.info(name))
    opts = Keyword.merge([ref_dt: Timex.now()], args_rest)

    overrides_map = overrides_map(module)

    force = if(get_in(opts, [:cmd_opts, :force]), do: true, else: false)

    checks_map = %{info: info, name: name, force: force, broom_module: broom_module(module)}

    Enum.reduce_while(@checks, checks_map, fn
      :status, checks_map -> execute_status(checks_map, opts)
      :execute, checks_map -> execute_cmd(checks_map, opts)
      what, checks_map -> apply_check(what, checks_map, module, overrides_map, opts)
    end)
    |> new_from_checks_accumulator()
  end

  def execute([_ | _] = args, opts) when is_list(opts) do
    Alfred.Execute.Args.auto({args, opts}) |> Enum.into(%{}) |> execute()
  end

  @doc since: "0.3.0"
  def on(_name, _opts) do
    :ok
  end

  @doc since: "0.3.0"
  def off(_name, _opts) do
    :ok
  end

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
      %{rc: :pending, detail: %{cmd: cmd, refid: refid}} -> ["PENDING", "{#{cmd}}", "@#{refid}"]
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
  def new_from_checks_accumulator({:cont, checks_map}) do
    new_from_checks_accumulator(checks_map)
  end

  def new_from_checks_accumulator(checks_map) do
    checks_map
    |> Map.take([:detail, :name, :rc])
    |> Map.put_new(:detail, :none)
    |> then(fn fields -> struct(__MODULE__, fields) end)
  end

  defmacrop put_detail_rc(rc, detail) do
    quote bind_quoted: [rc: rc, detail: detail] do
      checks_map = var!(checks_map)
      what = var!(what)

      detail = Map.get(checks_map, :detail, %{}) |> Map.merge(detail)

      {:halt, Map.merge(checks_map, %{what => rc, :rc => rc, :detail => detail})}
    end
  end

  defmacrop put_status_detail_rc(rc) do
    quote bind_quoted: [rc: rc] do
      checks_map = var!(checks_map)
      status = var!(status)
      what = var!(checks_map)

      cmd = if(match?(%{detail: %{cmd: _}}, status), do: status.detail.cmd, else: "unknown")

      merge_map = %{what => rc, rc: rc, cmd: cmd, detail: status.detail}

      {:halt, Map.merge(checks_map, merge_map)}
    end
  end

  defmacrop put_what_rc_cont(rc) do
    quote bind_quoted: [rc: rc], do: {:cont, Map.put_new(var!(checks_map), var!(what), rc)}
  end

  defmacrop put_final_rc(rc) do
    quote bind_quoted: [rc: rc], do: {:halt, Map.put_new(var!(checks_map), :rc, rc)}
  end

  @doc false
  def apply_check(what, checks_map, module, overrides, opts) do
    case {what, overrides} do
      {what, %{^what => true}} -> module.check(what, checks_map, opts)
      {what, _overrides} -> check(what, checks_map, opts)
    end
  end

  @doc false
  def check(:registered = what, checks_map, _opts) do
    case checks_map do
      # name is registered
      %{info: %{name: _}} -> put_what_rc_cont(:ok)
      %{info: {:not_found = rc, _name}} -> put_final_rc(rc)
    end
  end

  def check(:verify = what, %{status: status} = checks_map, _opts) do
    case status do
      %Alfred.Status{rc: :ok} -> put_what_rc_cont(:ok)
      %Alfred.Status{rc: rc} = status -> put_status_detail_rc(rc)
    end
  end

  def check(:compare = what, %{status: status, force: force} = checks_map, opts) do
    want_cmd = opts[:cmd]

    case status do
      %{detail: %{cmd: ^want_cmd}} when not force -> put_status_detail_rc(:ok)
      _ -> put_what_rc_cont(:not_equal)
    end
  end

  def check(:finalize = what, checks_map, _opts) do
    %{execute: {rc, exec_result}, track: track_result} = checks_map

    detail = %{cmd: exec_result.cmd, __execute__: exec_result, __track__: track_result}

    put_detail_rc(rc, detail)
  end

  def check(:track = what, checks_map, opts) do
    case checks_map do
      %{broom_module: :none = rc} -> rc
      %{broom_module: module, execute: {:pending, cmd}} -> module.track(cmd, opts)
      _ -> :ok
    end
    |> put_what_rc_cont()
  end

  def check(:ttl_info = what, %{info: info} = checks_map, opts) do
    %{ttl_ms: ttl_ms, seen_at: at} = info

    ttl_check({at, ttl_ms}, what, checks_map, opts)
  end

  @doc false
  def execute_cmd(checks_map, opts) do
    what = :execute
    %{status: status, info: %{callbacks: %{execute: {module, 2}}}} = checks_map

    case module.execute_cmd(status, opts) do
      {rc, result} when rc in [:ok, :pending] -> put_what_rc_cont({rc, result})
      {rc, result} -> put_detail_rc(rc, result)
    end
  end

  @doc false
  def execute_status(%{info: info} = checks_map, opts) do
    what = :status

    %{callbacks: %{status: {module, 2}}} = info

    module.status(info.name, opts) |> put_what_rc_cont()
  end

  @doc false
  def ttl_check({at, ttl_ms}, what, checks_map, opts) do
    ref_dt = Keyword.get(opts, :ref_dt)
    ttl_ms = Keyword.get(opts, :ttl_ms, ttl_ms)

    ttl_start_at = Timex.shift(ref_dt, milliseconds: ttl_ms * -1)

    # if either the device hasn't been seen or the DevAlias hasn't been updated then the ttl is expired
    if Timex.before?(ttl_start_at, at) do
      put_what_rc_cont(:ok)
    else
      put_final_rc({:ttl_expired, DateTime.diff(ref_dt, at, :millisecond)})
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
