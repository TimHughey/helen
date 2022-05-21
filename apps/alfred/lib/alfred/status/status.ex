defmodule Alfred.Status do
  @moduledoc """
  Generalized status of an `Alfred.Name`

  """

  defstruct name: :none, story: :none, rc: :not_found, __raw__: :none

  @type lookup_result() :: nil | {:ok, any()} | {:error, any()} | struct() | map()
  @type status_rc :: :ok | {:not_found, String.t()} | :busy | :timeout | {:ttl_expired, pos_integer()}

  @type t :: %__MODULE__{name: String.t(), story: map | struct, rc: status_rc(), __raw__: any}

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
      %{story: %{cmd: cmd}} -> cmd
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

  defmacrop halt(rc, story) do
    %{function: {what, _}} = __CALLER__

    quote bind_quoted: [rc: rc, story: story, what: what] do
      chk_map = var!(chk_map)
      merge = %{what => rc, story: merge_story(chk_map, story), rc: rc}

      {:halt, Map.merge(chk_map, merge)}
    end
  end

  @doc since: "0.3.0"
  @checks [:lookup, :raw, :busy, :timeout, :finalize]
  @spec status_now(%{:name => any, optional(any) => any}, any) :: binary | struct
  def status_now(%{name: name} = info, args) do
    chk_map = %{info: info, name: name}

    Enum.reduce_while(@checks, chk_map, fn
      :lookup, chk_map -> lookup(chk_map, info, args)
      :raw, %{lookup: raw} = chk_map -> continue(raw, :__raw__)
      :busy, chk_map -> busy(chk_map, args)
      :timeout, chk_map -> timeout(chk_map, args)
      :finalize, chk_map -> finalize(chk_map, args)
    end)
    |> log()
    |> take_fields(args)
    |> status_returned(args)
  end

  @doc false
  def status_returned(fields, args) do
    status = struct(__MODULE__, fields)

    cond do
      get_in(args, [:binary]) == true -> to_binary(status)
      true -> status
    end
  end

  @doc since: "0.4.9"
  def to_binary(%{name: name} = status, _opts \\ []) do
    case status do
      %{rc: :ok, story: <<_::binary>> = story} -> ["OK", story]
      %{rc: :ok, story: %{cmd: cmd}} -> ["OK", "{#{cmd}}"]
      %{rc: :ok, story: %{temp_c: _} = story} -> ["OK", to_binary_story(story)]
      %{rc: :busy, story: <<_::binary>> = story} -> ["BUSY", story]
      %{rc: :busy, story: %{cmd: cmd, refid: refid}} -> ["BUSY", "{#{cmd}}", "@#{refid}"]
      %{rc: :not_found} -> ["NOT_FOUND"]
      %{rc: {:ttl_expired, ms}} -> ["TTL_EXPIRED", "+#{ms}ms"]
      %{rc: {:timeout, ms}} -> ["TIMEOUT", "+#{ms}ms"]
      _ -> ["ERROR"]
    end
    |> then(fn story -> story ++ ["[#{name}]"] end)
    |> Enum.join(" ")
  end

  @doc false
  @story_keys [:relhum, :temp_c, :temp_f]
  def to_binary_story(story) do
    Enum.reduce(@story_keys, [], fn key, acc ->
      val = get_in(story, [key])

      case val do
        x when is_float(x) -> [to_string(key), "=", to_string(Float.round(x, 2))]
        x when is_integer(x) -> [to_string(key), "=", to_string(x)]
        _ -> []
      end
      |> then(fn list -> [list | acc] end)
    end)
  end

  @doc false
  def busy(chk_map, _opts) do
    case chk_map.lookup.status do
      %{acked: false} = status -> halt(:busy, status)
      _ -> continue(:ok)
    end
  end

  @doc false
  @log_no [:ok, :busy]
  @log_tags [status: :error, module: __MODULE__]
  def log(chk_map) do
    case chk_map do
      %{rc: rc} when rc in @log_no -> :dont_log
      %{name: name, rc: _} -> Keyword.put(@log_tags, :name, name) |> Betty.app_error()
    end

    # NOTE: passthrough the chk_map
    chk_map
  end

  @doc false
  @story_drop [:__meta__, :__struct__]
  def merge_story(_chk_mao, :none), do: :none

  def merge_story(chk_map, merge_this) do
    existing = Map.get(chk_map, :story, %{})
    clean = Map.drop(merge_this, @story_drop)

    Map.merge(existing, clean)
  end

  @doc false
  def finalize(chk_map, _opts), do: halt(:ok, chk_map.lookup.status)

  @doc false
  @allowed_rc [:busy, :error, :ok, :timeout]
  def lookup(chk_map, info, args) do
    opts = Enum.into(args, [])

    lookup = Alfred.Name.Callback.invoke(info, [info, opts], :status_lookup)

    case lookup do
      %{} -> continue(lookup)
      {:error, :no_data = rc} -> halt(rc, %{})
      {rc, %{} = story} when rc in @allowed_rc -> halt(rc, story)
      {rc, <<_::binary>> = story} when rc in @allowed_rc -> halt(rc, story)
      _ -> halt(:error, %{})
    end
  end

  @essential_fields [:story, :name, :rc]
  def take_fields(chk_map, opts) do
    # NOTE: only populate :__raw__ if requested
    extra_fields = if get_in(opts, [:raw]) == true, do: [:__raw__], else: []
    take_fields = @essential_fields ++ extra_fields

    Map.take(chk_map, take_fields)
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
