defmodule Alfred.ExecResult do
  alias __MODULE__

  alias Alfred.ExecCmd
  alias Alfred.MutableStatus

  defstruct name: nil,
            rc: nil,
            cmd: "unknown",
            refid: nil,
            track_timeout_ms: nil,
            will_notify_when_released: false,
            instruct: :none

  @type exec_rc :: :ok | :pending | :not_found | {:ttl_expired, pos_integer()} | {:invalid, String.t()}

  @type t :: %__MODULE__{
          name: String.t(),
          rc: exec_rc(),
          cmd: String.t(),
          refid: nil | String.t(),
          track_timeout_ms: nil | pos_integer(),
          will_notify_when_released: boolean(),
          instruct: :none | struct()
        }

  def error(name, rc), do: %ExecResult{name: name, rc: rc}

  def from_cmd(%ExecCmd{} = ec, opts) do
    case opts[:rc] do
      x when is_nil(x) or x == :ok ->
        %ExecResult{
          name: ec.name,
          rc: :ok,
          cmd: ec.cmd,
          refid: opts[:refid],
          track_timeout_ms: opts[:track_timeout_ms],
          will_notify_when_released: Keyword.get(opts, :will_notify, false),
          instruct: opts[:instruct]
        }

      x when is_atom(x) ->
        invalid(ec, x)
    end
  end

  def from_status(%MutableStatus{} = status) do
    case status do
      %MutableStatus{ttl_expired?: true} -> ttl_expired(status)
      %MutableStatus{found?: false} -> not_found(status)
    end
  end

  def invalid(%ExecCmd{} = ec, rc) when is_atom(rc) do
    er = %ExecResult{name: ec.name, cmd: ec.cmd}

    case rc do
      :callback_failed -> %ExecResult{er | rc: {:invalid, "callback failed"}}
      :immutable -> %ExecResult{er | rc: {:invalid, "must be a mutable"}}
      :missing -> %ExecResult{er | rc: {:invalid, "name is missing"}}
      :unknown -> %ExecResult{er | rc: {:invalid, "name is unknown"}}
    end
  end

  def invalid(%ExecCmd{name: name, invalid_reason: x}), do: %ExecResult{name: name, rc: {:invalid, x}}

  @doc "Log a `Betty.app_error/1` for an ExecResult"
  @doc since: "0.2.10"
  def log_failure(%ExecResult{} = er, opts) do
    opts = Keyword.put_new(opts, :name, er.name)
    {mod_or_server, opts_rest} = Keyword.split(opts, [:module, :server_name, :name])

    # ensure at least the identifier :module is in tags
    tags = if(mod_or_server == [], do: [module: ExecResult], else: mod_or_server) ++ [execute: true]

    case er do
      %ExecResult{rc: {:ttl_expired, _}} -> {:rc, :ttl_expired}
      %ExecResult{rc: rc} -> {:rc, rc}
    end
    # create a tuple for pipeline
    |> then(fn tag -> {er, [tag | tags]} end)
    # send the tags off to Bettu
    |> tap(fn {_er, tags} -> Betty.app_error_v2(tags, opts_rest) end)
    # return the original ExecResult
    |> then(fn {er, _} -> er end)
  end

  @doc """
  Log `ExecResult` failure depending on value of `:rc` field

  When `:rc` is anything other than `:ok` or `:pending` an error row is inserted into
  the operational timeseries database via `Alfred.ExecCmd.log_failure/2`.
  """
  @doc since: "0.2.10"
  def log_failure_if_needed(%ExecResult{rc: rc} = er, _opts) when rc in [:ok, :pending], do: er
  def log_failure_if_needed(%ExecResult{} = er, opts), do: log_failure(er, opts)

  def not_found(%MutableStatus{name: name}), do: %ExecResult{name: name, cmd: "unknown", rc: :not_found}
  def no_change(%ExecCmd{name: name, cmd: cmd}), do: %ExecResult{name: name, cmd: cmd, rc: :ok}

  def ok(%ExecCmd{name: name, instruct: instruct}, %_{} = te) do
    %ExecResult{
      name: name,
      rc: :ok,
      cmd: te.cmd,
      refid: te.refid,
      track_timeout_ms: te.track_timeout_ms,
      will_notify_when_released: if(is_pid(te.notify_pid), do: true, else: false),
      instruct: instruct
    }
  end

  def ttl_expired(%MutableStatus{name: name, status_at: at}) do
    rc = {:ttl_expired, DateTime.utc_now() |> DateTime.diff(at, :millisecond)}

    %ExecResult{name: name, rc: rc}
  end

  @doc """
  Convert an `ExecResult` to a sratus binary

  """
  @doc since: "0.2.10"
  def to_binary(%ExecResult{} = er, _opts \\ []) do
    case er do
      %ExecResult{rc: :ok} -> ["{#{er.cmd}}", "OK"]
      %ExecResult{rc: :pending} -> ["@#{er.refid}", "{#{er.cmd}}", "PENDING"]
      %ExecResult{rc: :not_found} -> ["NOT_FOUND"]
      %ExecResult{rc: {:ttl_expired, ms}} -> ["+#{ms}ms", "TTL_EXPIRED"]
      %ExecResult{rc: :invalid} -> ["INVALID"]
    end
    |> then(fn details -> ["[#{er.name}]" | details] end)
    |> then(fn final -> Enum.reverse(final) |> Enum.join(" ") end)
  end
end
