defmodule Alfred.Status do
  @moduledoc """
  Generalized status of an `Alfred.Name`

  """

  defstruct name: :none, detail: :none, rc: :not_found, __raw__: :none

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
  def not_found(name), do: struct(__MODULE__, name: name)

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
      merge = %{what => rc, detail: merge_detail(chk_map, detail), rc: rc}

      {:halt, Map.merge(chk_map, merge)}
    end
  end

  @doc since: "0.3.0"
  @checks [:lookup, :raw, :busy, :timeout, :finalize]
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
  def busy(chk_map, _opts) do
    case chk_map.lookup.status do
      %{acked: false} = status -> halt(:busy, status)
      _ -> continue(:ok)
    end
  end

  @doc false
  @detail_drop [:__meta__, :__struct__]
  def merge_detail(_chk_mao, :none), do: :none

  def merge_detail(chk_map, merge_this) do
    existing = Map.get(chk_map, :detail, %{})
    clean = Map.drop(merge_this, @detail_drop)

    Map.merge(existing, clean)
  end

  @doc false
  def finalize(chk_map, _opts), do: halt(:ok, chk_map.lookup.status)

  @doc false
  def lookup(chk_map, info, args) do
    opts = Enum.into(args, [])

    lookup = Alfred.Name.Callback.invoke(info, [info, opts], :status_lookup)

    case lookup do
      %{} -> continue(lookup)
      {:error, :no_data = rc} -> halt(rc, %{})
    end
  end

  @doc false
  @timeout %{acked: true, orphaned: true}
  @unit :millisecond
  def timeout(%{lookup: %{status: status, seen_at: seen_at}} = chk_map, opts) do
    cond do
      match?(@timeout, status) and Timex.before?(seen_at, status.acked_at) ->
        ref_dt = opts[:ref_dt] || Timex.now()
        rc = {:timeout, Timex.diff(ref_dt, status.acked_at, @unit)}

        halt(rc, status)

      true ->
        continue(:ok)
    end
  end
end
