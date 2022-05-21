defmodule Alfred.Execute do
  @moduledoc """
  Generalized execute of an `Alfred.Name`

  """

  defstruct name: :none, cmd: "unknown", story: :none, rc: nil

  @callback execute_cmd(any(), opts :: list()) :: any()

  defmacrop continue(val) do
    %{function: {what, _}} = __CALLER__

    quote bind_quoted: [val: val, what: what] do
      {:cont, Map.put(var!(chk_map), what, val)}
    end
  end

  defmacrop halt(rc, story) do
    %{function: {what, _}} = __CALLER__

    quote bind_quoted: [rc: rc, story: story, what: what] do
      chk_map = var!(chk_map)

      story =
        if(story == :none, do: :none, else: Map.get(chk_map, :story, %{}) |> Map.merge(story))

      {:halt, Map.merge(chk_map, %{what => rc, rc: rc, story: story})}
    end
  end

  @doc since: "0.3.0"
  @checks [:status, :verify, :compare, :execute_cmd, :finalize]
  def execute_now(%{name: name} = info, args) do
    chk_map = %{
      info: info,
      name: name,
      force: if(get_in(args, [:cmd_opts, :force]) == true, do: true, else: false)
    }

    Enum.reduce_while(@checks, chk_map, fn
      :status, chk_map -> status(chk_map, info, args)
      :verify, chk_map -> verify(chk_map)
      :compare, chk_map -> compare(chk_map, args)
      :execute_cmd, chk_map -> execute_cmd(chk_map, info, args)
      :finalize, chk_map -> finalize(chk_map)
    end)
    |> new_from_checks_accumulator()
  end

  @doc false
  def new_from_checks_accumulator(chk_map) do
    cmd = if(match?(%{story: %{cmd: _}}, chk_map), do: chk_map.story.cmd, else: nil)

    if(is_binary(cmd), do: put_in(chk_map, [:cmd], cmd), else: chk_map)
    |> then(fn fields -> struct(__MODULE__, fields) end)
  end

  def not_found(name), do: struct(__MODULE__, name: name, rc: :not_found)

  @doc since: "0.3.0"
  def toggle(_name, _opts) do
    :ok
  end

  @doc """
  Convert an `Alfred.Execute` to a status binary

  """
  @doc since: "0.3.0"
  def to_binary(%{name: name} = execute, _opts \\ []) do
    case execute do
      %{rc: :ok, story: <<_::binary>> = story} -> ["OK", story]
      %{rc: :ok, story: %{cmd: cmd}} -> ["OK", "{#{cmd}}"]
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

  ##
  ## END OF PUBLIC API
  ##

  @doc false
  def compare(%{status: status, force: force} = chk_map, opts) do
    want_cmd = opts[:cmd]

    case status do
      _status when force -> continue(:force)
      %{story: %{cmd: ^want_cmd} = story} -> halt(:ok, story)
      _ -> continue(:not_equal)
    end
  end

  @doc false
  def execute_cmd(%{status: status} = chk_map, info, args) do
    raw = Alfred.Status.raw(status)
    opts = Enum.into(args, [])

    execute = Alfred.Name.Callback.invoke(info, [raw, opts], :execute_cmd)

    case execute do
      {rc, result} when rc in [:ok, :busy] -> continue({rc, result})
      {rc, result} -> halt(rc, result)
    end
  end

  @doc false
  def finalize(%{execute_cmd: {rc, story}} = chk_map), do: halt(rc, story)

  @doc false
  def status(chk_map, info, args) do
    # NOTE: request raw populated by status_lookup/2
    args = put_in(args, [:raw], true)

    Alfred.Name.Callback.invoke(info, args, :status) |> continue()
  end

  @doc false
  def verify(%{status: status} = chk_map) do
    case status do
      %Alfred.Status{rc: :ok} -> continue(:ok)
      %Alfred.Status{rc: rc, story: story} -> halt(rc, story)
    end
  end

  @mod_attribute :alfred_execute_use_opts

  # coveralls-ignore-start

  @doc false
  defmacro __using__(use_opts) do
    quote bind_quoted: [use_opts: use_opts] do
      Alfred.Execute.put_attribute(__MODULE__, use_opts)

      @behaviour Alfred.Execute
    end
  end

  @doc false
  def put_attribute(module, use_opts) do
    Module.register_attribute(module, @mod_attribute, persist: true)
    Module.put_attribute(module, @mod_attribute, use_opts)
  end

  # coveralls-ignore-stop
end
