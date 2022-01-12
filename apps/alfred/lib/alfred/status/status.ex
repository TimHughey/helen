defmodule Alfred.Status do
  @moduledoc """
  Generalized status of an `Alfred.KnownName`

  """

  defstruct name: :none, detail: %{}, rc: {:unset, :default}

  @type lookup_result() :: nil | {:ok, any()} | {:error, any()} | struct() | map()
  @type nature() :: :cmds | :datapoints
  @type status_mutable :: map()
  @type status_immutable :: map()
  @type status_detail :: status_mutable | status_immutable
  @type status_rc :: :ok | {:not_found, String.t()} | :pending | :orphan | {:ttl_expired, pos_integer()}

  @type t :: %__MODULE__{name: String.t(), detail: status_detail(), rc: status_rc()}

  @callback status(binary(), list()) :: %__MODULE__{}
  @callback status_check(atom(), map() | struct(), list()) :: :ok | {atom(), any()}
  @callback status_lookup(map(), list()) :: lookup_result()

  @optional_callbacks [status_check: 3]

  defmacro __using__(use_opts) do
    quote do
      Alfred.Status.overrides_attribute_put(__MODULE__, unquote(use_opts))

      @behaviour Alfred.Status
      def status(name, opts), do: Alfred.Status.of_name(name, __MODULE__, @alfred_status_overrides, opts)
    end
  end

  @doc false
  def overrides_attribute_put(module, use_opts) do
    overrides = use_opts[:overrides] || []
    overrides_map = Enum.map(overrides, fn key -> {key, true} end) |> Enum.into(%{})

    Module.put_attribute(module, :alfred_status_overrides, overrides_map)
  end

  # Creating the Status of a Name
  #
  # A list of checks are reduced to create the status.  The result of each reduction determines if
  # the checks should continue or stop (e.g. due to check failure).  The end result is a details
  # map to use as the source data for the final Alfred.Status.
  #
  #  1. Get Alfred.Name info
  #     a. confirm name is registered
  #     b. confirm ttl isn't expired
  #
  #  2. Lookup the name via status_lookup/3 (requires name, nature and opts)
  #     a. confirm the name exists (low probability fail if Alfred.Name exists and TTL isn't expired)
  #     b. confirm the ttl isn't expired (similar fail probability)
  #     c. nature == :cmds: check if the command is pending
  #     d. nature == :cmds: check if the command is orphaned
  #     e. confirm the status is good comprised of nature dependent checks
  #     f. assemble the status detail
  #
  #  3. If all checks are successful, create Alfred.Status from detail map
  #
  # Handling of failed or intermediate checks
  #
  #  1. When a check fails Alfred.Status :name and :rc are populated
  #  2. Intermediate status results (e.g. pending) __may__ populate detail
  #  3. Successful status populate :rc, :name and :detail
  #     a. :detail varies depending on the nature of the name (e.g. cmds vs. datapoints)
  #     b. the caller is responsible for interpreting the detail
  #
  @checks [:registered, :ttl_info, :lookup, :ttl_lookup, :pending, :orphan, :good, :detail]
  def of_name(name, module, overrides_map, opts) do
    default_opts = [ref_dt: Timex.now()]
    opts_all = Keyword.merge(default_opts, [{:name, name} | opts])

    checks_map = %{info: Alfred.Name.info(name), name: name}

    Enum.reduce(@checks, {:ok, checks_map}, fn
      # a check has failed or otherwise signals checking should stop
      _what, {:halt, _checks_map} = acc -> acc
      # detail created, no further checks necessary
      _what, {_rc, %{detail: _}} = acc -> acc
      # continue checks
      what, {_rc, checks_map} -> apply_check(what, checks_map, module, overrides_map, opts_all)
    end)
    |> new_from_checks_tuple()
  end

  @doc false
  def apply_check(what, checks_map, module, overrides, opts) do
    info = checks_map.info

    case {what, overrides} do
      {:lookup, _overrides} -> apply(module, :status_lookup, [info, opts])
      {what, %{^what => true}} -> apply(module, :check, [what, checks_map, opts])
      {what, _overrides} -> check(what, checks_map, opts)
    end
    |> checks_map_put(what, checks_map)
  end

  @doc false
  def new_from_checks_tuple({rc, checks_map}) do
    checks_map
    |> Map.take([:detail, :name, :rc])
    |> Map.put_new(:detail, :none)
    |> Map.put_new(:rc, rc)
    |> then(fn fields -> struct(__MODULE__, fields) end)
  end

  @doc false
  def check(:detail, %{lookup: lookup}, _opts) do
    case lookup do
      %{datapoints: [%{} = detail]} -> {:ok, detail}
      %{cmds: [cmd]} when is_struct(cmd) -> {:ok, Map.from_struct(cmd)}
      %{cmds: [cmd]} -> {:ok, cmd}
      _ -> :no_match
    end
  end

  def check(:good, %{lookup: lookup}, _opts) do
    case lookup do
      %{cmds: [%{acked: true}]} -> :ok
      %{datapoints: [%{}]} -> :ok
      _ -> :no_match
    end
  end

  # (aaa / bbb) orphan check
  def check(
        :orphan,
        %{lookup: %{cmds: [%{orphaned: true, acked_at: acked_at, cmd: cmd}], updated_at: at}},
        _opts
      ),
      do: orphan_rc(acked_at, cmd, at)

  def check(:pending, %{lookup: %{cmds: [%{acked: false} = cmd]}}, _opts) do
    {:pending, %{detail: Map.take(cmd, [:cmd, :refid, :sent_at])}}
  end

  def check(:registered, checks_map, _opts) do
    case checks_map do
      # name is registered
      %{info: %{name: _}} -> {:ok, checks_map}
      %{info: rc} -> rc
    end
  end

  @ttl_checks [:ttl_info, :ttl_lookup]
  def check(what, checks_map, opts) when what in @ttl_checks do
    # NOTE: this check is called twice, use what to drive which is checked
    case {what, checks_map} do
      # handle ttl check for info
      {:ttl_info, %{info: %{ttl_ms: ttl_ms, seen_at: at}}} -> {at, ttl_ms}
      {:ttl_lookup, %{lookup: %{ttl_ms: ttl_ms, updated_at: at}}} -> {at, ttl_ms}
    end
    |> ttl_check(opts)
  end

  def check(_what, _checks_map, _opts), do: :bad_match

  @doc false
  def orphan_rc(acked_at, cmd, updated_at) do
    if Timex.before?(updated_at, acked_at) do
      {:orphan, %{detail: %{cmd: cmd}}}
    else
      :ok
    end
  end

  # NOTE: lists used by checks_map_put/3
  @auto_merge_status [:registered]
  @exception_rc [:pending, :orphan]
  @unmatched_ok [:pending, :orphan]

  @doc false
  # NOTE: checks_map_put/3 returns the next accumulator value for the status check reduction
  def checks_map_put(result, what, checks_map) do
    case {result, what} do
      # check success, merge result into base check map
      {{:ok, %{} = merge}, what} when what in @auto_merge_status ->
        # signal the check (aka what) was successful
        Map.put(merge, what, :ok)
        # then merge the result map into the base of the check map
        |> then(fn override_map -> Map.merge(checks_map, override_map) end)
        |> then(fn checks_map -> {:ok, checks_map} end)

      # not found from registered or lookup or
      {{:not_found = rc, _name}, what} ->
        {:halt, Map.merge(checks_map, %{what => rc, :rc => rc})}

      # simple successful check by putting the rc in the check key
      {:ok, what} ->
        {:ok, Map.put(checks_map, what, :ok)}

      # handle status_lookup/3 success by putting the lookup result in check map base
      {%{} = result, :lookup} ->
        {:ok, Map.put(checks_map, :lookup, result)}

      # handle intermediate status result with detail provided (e.g. pending, orphan)
      {{rc, %{detail: _} = merge}, what} when rc in @exception_rc ->
        merge
        |> Map.put_new(what, rc)
        |> Map.put_new(:rc, rc)
        # wrapped in then/1 so merge is handled as overrides to checks_map
        |> then(fn merge -> Map.merge(checks_map, merge) end)
        |> then(fn checks_map -> {rc, checks_map} end)

      # checks that default to :ok when not matched via check/3
      {_rc, what} when what in @unmatched_ok ->
        {:ok, Map.put(checks_map, what, :ok)}

      # handle detail success
      {{rc, result}, :detail} ->
        checks_map
        |> Map.put_new(:detail, result)
        |> Map.put_new(:rc, rc)
        |> then(fn checks_map -> {rc, checks_map} end)

      {{:ttl_expired, _ms} = rc, what} ->
        {:halt, Map.merge(checks_map, %{what => rc, rc: rc})}

      # handle failed status checks (including lookup failures)
      {result, what} ->
        {:halt, Map.merge(checks_map, %{what => result, :rc => :error})}
    end
  end

  @doc false
  def ttl_check({at, ttl_ms}, opts) do
    ref_dt = Keyword.get(opts, :ref_dt)
    ttl_ms = Keyword.get(opts, :ttl_ms, ttl_ms)

    ttl_start_at = Timex.shift(ref_dt, milliseconds: ttl_ms * -1)

    # if either the device hasn't been seen or the DevAlias hasn't been updated then the ttl is expired
    if Timex.before?(ttl_start_at, at) do
      :ok
    else
      {:ttl_expired, DateTime.diff(ref_dt, at, :millisecond)}
    end
  end
end
