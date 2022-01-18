defmodule Alfred.Status do
  @moduledoc """
  Generalized status of an `Alfred.Name`

  """

  @rc_default {:unset, :default}

  defstruct name: :none, detail: :none, rc: @rc_default, __raw__: nil

  @type lookup_result() :: nil | {:ok, any()} | {:error, any()} | struct() | map()
  @type nature() :: :cmds | :datapoints
  @type status_mutable :: map()
  @type status_immutable :: map()
  @type status_detail :: status_mutable | status_immutable
  @type status_rc :: :ok | {:not_found, String.t()} | :pending | :orphan | {:ttl_expired, pos_integer()}

  @type t :: %__MODULE__{name: String.t(), detail: status_detail(), rc: status_rc()}

  @mod_attribute :alfred_status_overrides_map
  @callback status(binary(), list()) :: %__MODULE__{}
  @callback status_check(atom(), map() | struct(), list()) :: :ok | {atom(), any()}
  @callback status_lookup(map(), list()) :: lookup_result()

  @optional_callbacks [status_check: 3]

  @doc false
  defmacro __using__(use_opts) do
    quote bind_quoted: [use_opts: use_opts] do
      Alfred.Status.put_attribute(__MODULE__, use_opts)

      @behaviour Alfred.Status
      def status(name, opts), do: Alfred.Status.status(name, __MODULE__, opts)
    end
  end

  @doc false
  def put_attribute(module, use_opts) do
    Module.register_attribute(module, @mod_attribute, persist: true)
    overrides = use_opts[:overrides] || []

    [
      overrides: Enum.into(overrides, %{}, fn key -> {key, true} end)
    ]
    |> then(fn val -> Module.put_attribute(module, @mod_attribute, val) end)
  end

  @doc false
  def overrides_map(module) do
    get_in(module.__info__(:attributes), [@mod_attribute, :overrides])
  end

  @doc since: "0.3.0"
  def get_cmd(%__MODULE__{} = status) do
    case status do
      %{detail: %{cmd: cmd}} -> cmd
      _ -> "UNKNOWN"
    end
  end

  @doc since: "0.3.0"
  def raw(%Alfred.Status{__raw__: raw}), do: raw

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

  @doc since: "0.3.0"
  def status(%{name: name} = name_map, module, opts) when not is_map_key(name_map, :nature) do
    Alfred.Name.fake_name_info(name_map, module, opts)
    |> then(fn opts -> status(name, module, opts) end)
  end

  @checks [:registered, :ttl_info, :lookup, :ttl_lookup, :pending, :orphan, :finalize]
  # (aaa of bbb) invoked via status/2 injected into using module
  def status(<<_::binary>> = name, module, opts) do
    {info, opts_rest} = Keyword.pop(opts, :__name_info__, Alfred.Name.info(name))

    opts_all = Keyword.merge([ref_dt: Timex.now()], [{:name, name} | opts_rest])
    overrides_map = overrides_map(module)

    checks_map = %{info: info, name: name}

    Enum.reduce_while(@checks, checks_map, fn
      :lookup, checks_map -> execute_lookup(checks_map, opts_all)
      what, checks_map -> apply_check(what, checks_map, module, overrides_map, opts_all)
    end)
    |> new_from_checks_accumulator()

    # Enum.reduce(@checks, {:ok, checks_map}, fn
    #   # a check has failed or otherwise signals checking should stop
    #   _what, {:halt, _checks_map} = acc -> acc
    #   # detail created, no further checks necessary
    #   _what, {_rc, %{detail: _}} = acc -> acc
    #   # continue checks
    #   what, {_rc, checks_map} -> apply_check(what, checks_map, module, overrides_map, opts_all)
    # end)
    # |> new_from_checks_tuple()
  end

  # (aaa of bbb) typically invoked from Alfred.status/2
  def status(<<_::binary>> = name, opts) do
    info = Alfred.Name.info(name)
    opts_all = [{:__name_info__, info} | opts]

    case info do
      %{name: name, callbacks: %{status: {module, _}}} -> module.status(name, opts_all)
      %{callbacks: %{status: nil}} -> {:error, :status_not_supported}
      {:not_found = rc, name} -> struct(__MODULE__, name: name, rc: rc, detail: :none)
      rc -> rc
    end
  end

  @doc false
  def new_from_checks_accumulator({:cont, checks_map}) do
    new_from_checks_accumulator(checks_map)
  end

  def new_from_checks_accumulator(checks_map) do
    checks_map
    |> Map.take([:detail, :name, :rc])
    |> Map.put(:__raw__, Map.get(checks_map, :lookup, :none))
    |> Map.put_new(:detail, :none)
    |> then(fn fields -> struct(__MODULE__, fields) end)
  end

  # @doc false
  # def apply_check(what, checks_map, module, overrides, opts) do
  #   info = checks_map.info
  #
  #   case {what, overrides} do
  #     {:lookup, _overrides} -> module.status_lookup(info, opts)
  #     {what, %{^what => true}} -> module.check(what, checks_map, opts)
  #     {what, _overrides} -> check(what, checks_map, opts)
  #   end
  #   |> checks_map_put(what, checks_map)
  # end
  #
  # @doc false
  # def new_from_checks_tuple({rc, checks_map}) do
  #   checks_map
  #   |> Map.take([:detail, :name, :rc])
  #   |> Map.put(:__raw__, Map.get(checks_map, :lookup, :none))
  #   |> Map.put_new(:detail, :none)
  #   |> Map.put_new(:rc, rc)
  #   |> then(fn fields -> struct(__MODULE__, fields) end)
  # end

  defmacrop put_detail_rc(rc, detail) do
    quote bind_quoted: [rc: rc, detail: detail] do
      checks_map = var!(checks_map)
      what = var!(what)

      detail = Map.get(checks_map, :detail, %{}) |> Map.merge(detail)

      {:halt, Map.merge(checks_map, %{what => rc, :rc => rc, :detail => detail})}
    end
  end

  defmacrop put_cmd_detail_rc(rc) do
    quote bind_quoted: [rc: rc] do
      checks_map = var!(checks_map)
      what = var!(what)
      cmd = var!(cmd)

      cmd_map = if(is_struct(cmd), do: Map.from_struct(cmd), else: cmd)

      {:halt, Map.merge(checks_map, %{what => rc, :rc => rc, :detail => cmd_map})}
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
  def check(:finalize = what, checks_map, _opts) do
    %{lookup: lookup} = checks_map

    case lookup do
      %{datapoints: [%{} = detail]} -> put_detail_rc(:ok, detail)
      %{cmds: [%{acked: true} = cmd]} -> put_cmd_detail_rc(:ok)
      _ -> put_detail_rc(:error, %{})
    end
  end

  # @doc false
  # def check(:detail, %{lookup: lookup}, _opts) do
  #   case lookup do
  #     %{datapoints: [%{} = detail]} -> {:ok, detail}
  #     %{cmds: [cmd]} when is_struct(cmd) -> {:ok, Map.from_struct(cmd)}
  #     %{cmds: [cmd]} -> {:ok, cmd}
  #     _ -> :no_match
  #   end
  # end

  # def check(:good, %{lookup: lookup}, _opts) do
  #   case lookup do
  #     %{cmds: [%{acked: true}]} -> :ok
  #     %{datapoints: [%{}]} -> :ok
  #     _ -> :no_match
  #   end
  # end

  # (aaa / bbb) orphan check
  def check(:orphan = what, checks_map, _opts) do
    %{lookup: %{cmds: cmds, updated_at: at}} = checks_map

    case cmds do
      [%{orphaned: true} = cmd] -> orphan_rc(cmd, at, what, checks_map)
      _ -> put_what_rc_cont(:ok)
    end
  end

  @pending_keys [:cmd, :refid, :sent_at]
  def check(:pending = what, checks_map, _opts) do
    %{lookup: %{cmds: cmds}} = checks_map

    case cmds do
      [%{acked: false} = cmd] -> put_detail_rc(:pending, Map.take(cmd, @pending_keys))
      _ -> put_what_rc_cont(:ok)
    end
  end

  # def check(:pending, %{lookup: %{cmds: [%{acked: false} = cmd]}}, _opts) do
  #   {:pending, %{detail: Map.take(cmd, [:cmd, :refid, :sent_at])}}
  # end

  def check(:registered = what, checks_map, _opts) do
    case checks_map do
      # name is registered
      %{info: %{name: _}} -> put_what_rc_cont({:ok})
      %{info: {:not_found = rc, _name}} -> put_final_rc(rc)
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
    |> ttl_check(what, checks_map, opts)
  end

  @doc false
  def execute_lookup(checks_map, opts) do
    what = :lookup
    %{info: %{callbacks: %{status: {module, 2}}} = name_info} = checks_map

    case module.status_lookup(name_info, opts) do
      nil -> put_detail_rc(:no_data, %{})
      %{} = result -> put_what_rc_cont(result)
    end
  end

  @doc false
  def orphan_rc(cmd_map, updated_at, what, checks_map) do
    %{acked_at: acked_at} = cmd_map

    if Timex.before?(updated_at, acked_at) do
      put_detail_rc(:orphan, cmd_map)
    else
      put_what_rc_cont(:ok)
    end
  end

  # NOTE: lists used by checks_map_put/3
  # @auto_merge_status [:registered]
  # @exception_rc [:pending, :orphan]
  # @unmatched_ok [:pending, :orphan]
  #
  # @doc false
  # # NOTE: checks_map_put/3 returns the next accumulator value for the status check reduction
  # def checks_map_put(result, what, checks_map) do
  #   case {result, what} do
  #     # check success, merge result into base check map
  #     {{:ok, %{} = merge}, what} when what in @auto_merge_status ->
  #       # signal the check (aka what) was successful
  #       Map.put(merge, what, :ok)
  #       # then merge the result map into the base of the check map
  #       |> then(fn override_map -> Map.merge(checks_map, override_map) end)
  #       |> then(fn checks_map -> {:ok, checks_map} end)
  #
  #     # not found from registered or lookup or
  #     {{:not_found = rc, _name}, what} ->
  #       {:halt, Map.merge(checks_map, %{what => rc, :rc => rc})}
  #
  #     # simple successful check by putting the rc in the check key
  #     {:ok, what} ->
  #       {:ok, Map.put(checks_map, what, :ok)}
  #
  #     # handle status_lookup/3 success by putting the lookup result in check map base
  #     {%{} = result, :lookup} ->
  #       {:ok, Map.put(checks_map, :lookup, result)}
  #
  #     # handle intermediate status result with detail provided (e.g. pending, orphan)
  #     {{rc, %{detail: _} = merge}, what} when rc in @exception_rc ->
  #       merge
  #       |> Map.put_new(what, rc)
  #       |> Map.put_new(:rc, rc)
  #       # wrapped in then/1 so merge is handled as overrides to checks_map
  #       |> then(fn merge -> Map.merge(checks_map, merge) end)
  #       |> then(fn checks_map -> {rc, checks_map} end)
  #
  #     # checks that default to :ok when not matched via check/3
  #     {_rc, what} when what in @unmatched_ok ->
  #       {:ok, Map.put(checks_map, what, :ok)}
  #
  #     # handle detail success
  #     {{rc, result}, :detail} ->
  #       checks_map
  #       |> Map.put_new(:detail, result)
  #       |> Map.put_new(:rc, rc)
  #       |> then(fn checks_map -> {rc, checks_map} end)
  #
  #     {{:ttl_expired, _ms} = rc, what} ->
  #       {:halt, Map.merge(checks_map, %{what => rc, rc: rc})}
  #
  #     # handle failed status checks (including lookup failures)
  #     {result, what} ->
  #       {:halt, Map.merge(checks_map, %{what => result, :rc => :error})}
  #   end
  # end

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
end
