defmodule Alfred.Status do
  @moduledoc """
  Generalized status of an `Alfred.Name`

  """

  defstruct name: :none, detail: :none, rc: nil, __raw__: :none

  @type lookup_result() :: nil | {:ok, any()} | {:error, any()} | struct() | map()
  @type status_rc :: :ok | {:not_found, String.t()} | :busy | :timeout | {:ttl_expired, pos_integer()}

  @type t :: %__MODULE__{name: String.t(), detail: map | struct, rc: status_rc(), __raw__: any}

  @callback status_lookup(map(), map()) :: lookup_result()

  # coveralls-ignore-start

  @doc false
  defmacro __using__(use_opts) do
    quote bind_quoted: [use_opts: use_opts] do
      Alfred.Status.put_attribute(__MODULE__, use_opts)

      @behaviour Alfred.Status
    end
  end

  @mod_attribute :alfred_status_use_opts

  @doc false
  def put_attribute(module, use_opts) do
    Module.register_attribute(module, @mod_attribute, persist: true)
    Module.put_attribute(module, @mod_attribute, use_opts)
  end

  # coveralls-ignore-stop

  @doc since: "0.3.0"
  def get_cmd(%__MODULE__{} = status) do
    case status do
      %{detail: %{cmd: cmd}} -> cmd
      _ -> "UNKNOWN"
    end
  end

  @doc false
  @not_found [detail: :none, rc: :not_found]
  def not_found(name), do: struct(__MODULE__, [{:name, name} | @not_found])

  @doc since: "0.3.0"
  def raw(%Alfred.Status{__raw__: raw}), do: raw

  defmacrop continue(val, what \\ :auto) do
    %{function: {func, _}} = __CALLER__

    quote bind_quoted: [val: val, func: func, what: what] do
      what = if(what == :auto, do: func, else: what)

      {:cont, Map.put(var!(chk_map), what, val)}
    end
  end

  defmacrop halt(rc, detail) do
    %{function: {what, _}} = __CALLER__

    quote bind_quoted: [rc: rc, detail: detail, what: what] do
      chk_map = var!(chk_map)
      detail = if(detail == :none, do: :none, else: Map.get(chk_map, :detail, %{}) |> Map.merge(detail))

      {:halt, Map.merge(chk_map, %{what => rc, rc: rc, detail: detail})}
    end
  end

  @doc since: "0.3.0"
  @checks [:lookup, :raw, :busy, :timeout, :finalize]
  # (aaa of bbb) invoked via status/2 injected into using module
  def status_now(%{name: name} = info, args) do
    chk_map = %{info: info, name: name}

    Enum.reduce_while(@checks, chk_map, fn
      :lookup, chk_map -> lookup(chk_map, info, args)
      :raw, %{lookup: raw} = chk_map -> continue(raw, :__raw__)
      :busy, chk_map -> busy(chk_map, args)
      :timeout, chk_map -> timeout(chk_map, args)
      :finalize, chk_map -> finalize(chk_map, args)
    end)
    |> Map.take([:detail, :name, :__raw__, :rc])
    |> then(fn fields -> struct(__MODULE__, fields) end)
  end

  @doc false
  @busy_keys [:cmd, :refid, :sent_at]
  def busy(chk_map, _opts) do
    %{lookup: %{cmds: cmds}} = chk_map

    case cmds do
      [%{acked: false} = cmd] -> halt(:busy, Map.take(cmd, @busy_keys))
      _ -> continue(:ok)
    end
  end

  @doc false
  def finalize(chk_map, _opts) do
    %{lookup: lookup} = chk_map

    case lookup do
      %{datapoints: [%{} = detail]} -> halt(:ok, detail)
      %{cmds: [%{acked: true} = cmd]} -> halt(:ok, cmd)
      _ -> halt(:error, %{})
    end
  end

  @doc false
  def lookup(chk_map, info, args) do
    opts = Enum.into(args, [])

    Alfred.Name.Callback.invoke(info, [info, opts], :status_lookup) |> continue()
  end

  @doc false
  def timeout(%{lookup: %{cmds: [cmd], updated_at: at}} = chk_map, opts) do
    ref_dt = opts[:ref_dt] || Timex.now()

    acked_before? = Timex.before?(at, cmd.acked_at)

    case {cmd, acked_before?} do
      {%{acked: true, orphaned: true}, true} ->
        {:timeout, Timex.diff(ref_dt, cmd.acked_at, :millisecond)} |> halt(cmd)

      _ ->
        continue(:ok)
    end
  end

  @doc false
  def timeout(chk_map, _opts), do: continue(:ok)
end
