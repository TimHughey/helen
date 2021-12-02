defmodule Alfred do
  require Logger

  @moduledoc """
  Master of known names
  """

  alias Alfred.{ExecCmd, ExecResult}
  alias Alfred.{ImmutableStatus, MutableStatus}
  alias Alfred.JustSaw
  alias Alfred.{KnownName, Names}
  alias Alfred.Notify
  alias Alfred.Notify.Ticket

  @doc """
  Execute an `Alfred.ExecCmd` for a known name

  The `Alfred.ExecCmd` is forwarded to the responsible party (e.g. module, server, function)
  specified via `Alfred.just_saw/2`. This function always returns an `Alfred.ExecResult`.

  ```
  # assembles the Alfred.ExecCmd from opts
  result = Alfred.execute("known name", cmd: "on")

  # same as above using the actual struct
  result = %Alfred.ExecCmd{name: "known name", cmd: "on"} |> Alfred.execute()
  ```
  """
  @doc since: "0.2.0"
  def execute(name_or_ec, opts \\ [])

  def execute(name, opts) when is_binary(name) and is_list(opts) do
    {wanted_opts, rest_opts} = Keyword.split(opts, [:cmd, :params, :cmd_opts, :pub_opts])

    # NOTE:
    # 1. :params in opts map to :cmd_params in ExecCmd
    # 2. minimal validation is performed here; see Alfred.ExecCmd.validate/1
    for {key, val} <- wanted_opts, reduce: %ExecCmd{name: name} do
      acc ->
        case key do
          :params -> %ExecCmd{acc | cmd_params: if(is_list(val), do: Enum.into(val, %{}), else: val)}
          :cmd -> %ExecCmd{acc | cmd: val}
          :cmd_opts -> %ExecCmd{acc | cmd_opts: val}
          :pub_opts -> %ExecCmd{acc | pub_opts: val}
        end
    end
    |> execute(rest_opts)
  end

  def execute(%ExecCmd{valid: :unchecked} = ec, opts), do: ExecCmd.validate(ec) |> execute(opts)

  def execute(%ExecCmd{valid: :yes} = ec, opts) do
    kn = names_lookup(ec.name, opts)

    try do
      case kn do
        %KnownName{valid?: false} -> ExecResult.from_cmd(ec, rc: :unknown)
        %KnownName{missing?: true} -> ExecResult.from_cmd(ec, rc: :missing)
        %KnownName{mutable?: false} -> ExecResult.from_cmd(ec, rc: :immutable)
        %KnownName{callback: {:server, server}} -> GenServer.call(server, {:execute, ec})
        %KnownName{callback: func} when is_function(func) -> func.(ec, opts)
        %KnownName{callback: {:module, mod}} -> mod.execute(ec)
      end
    rescue
      error ->
        Logger.error("#{inspect(error)}\n#{Exception.format_stacktrace()}")
        ExecResult.from_cmd(ec, rc: :callback_failed)
    catch
      kind, value ->
        Logger.error("#{kind}\n#{inspect(value, pretty: true)}\n#{Exception.format_stacktrace()}")
        ExecResult.from_cmd(ec, rc: :callback_failed)
    end
  end

  def execute(%ExecCmd{valid: :no} = ec, _opts), do: ExecResult.invalid(ec)

  @doc """
  Registers a known name

  The registration of a name enables `Alfred` to dispatch status and execute
  actions to the appropriate subsystems.

  Parties registered for notfications via `Alfred.notify_register/1` are sent
  `{Alfred, Alfred.Notify.Memo}` messages when a name is seen.

  ## Examples:
      iex> utc_now = DateTime.utc_now()
      iex> seen_list = [
      ...>   %SeenName{name: "name1", ttl_ms: 1000, seen_at: utc_now},
      ...>   %SeenName{name: "name2", ttl_ms: 1000},
      ...> ]
      iex> callback = {:module, SomeModule}
      iex> %Alfred.JustSaw{mutable?: true, callback: callback, seen_list: seen_list}
      ...> |> Alfred.just_saw()
      iex> ["name1", "name2"]

      iex> %Alfred.JustSaw{} |> Alfred,just_saw([names_server: AlfredSim.Names])
      iex> []

  ## Returns:
    1. `["name1", "name2"]`    -> list of valid names from seen list
    2. `[]`                    -> no valid names or empty seen list
    3. `{:no_server, atom()}`  -> Alfred.Names.Server (or :names_server) isn't available

  ## Opts as of list of atoms
  1. `:names_server`   -> use a names server other than `Alfred.Names.Server`
  2. `:notify_server`  -> use a notify server other than `Alfred.Notify.Server`

  """
  @doc since: "0.2.0"
  def just_saw(%JustSaw{} = js, opts \\ []) when is_list(opts) do
    with known_names when is_list(known_names) and known_names != [] <- JustSaw.to_known_names(js),
         names when is_list(names) <- Names.Server.call({:just_saw, known_names}, opts),
         :ok <- Notify.Server.cast({:notify, js.seen_list}, opts) do
      names
    else
      [] -> []
      error -> error
    end
  end

  def names_available?(name, opts \\ []) do
    not names_exists?(name, opts)
  end

  def names_delete(name, opts \\ [])
      when is_binary(name)
      when is_list(opts) do
    {:delete, name} |> Names.Server.call(opts)
  end

  def names_exists?(name, opts \\ [])
      when is_binary(name)
      when is_list(opts) do
    case names_lookup(name, opts) do
      %KnownName{valid?: x} -> x
      _ -> false
    end
  end

  @known_default_opts [names: true, timezone: "America/New_York"]
  def names_known(opts \\ @known_default_opts) when is_list(opts) do
    {opts, rest} = Keyword.split(opts, [:names, :details, :seen_ago, :seen_at])
    opts_map = Enum.into(opts, %{})
    timezone = opts[:timezone] || "America/New_York"

    for %KnownName{} = kn <- Names.Server.call(:known, rest) do
      case opts_map do
        %{names: true} -> kn.name
        %{details: true} -> kn
        %{seen_ago: true} -> {kn.name, ago_ms(kn.seen_at)}
        %{seen_at: true} -> {kn.name, Timex.to_datetime(kn.seen_at, timezone)}
        _ -> {:opts, [:details, :names, :seen_ago, :seen_at]}
      end
    end
  end

  def names_lookup(name, opts \\ [])
      when is_binary(name)
      when is_list(opts) do
    Names.Server.call({:lookup, name}, opts)
  end

  @type notify_server_opts :: [notify_server: atom()]
  @type notify_frequency_opts :: :all | [interval_ms: pos_integer()]
  @type notify_register_opts() :: [
          name: binary(),
          pid: pid(),
          link: boolean(),
          ttl_ms: non_neg_integer(),
          missing_ms: pos_integer(),
          frequency: notify_frequency_opts(),
          notify_server: atom()
        ]
  @spec notify_register(notify_register_opts()) :: {:ok, Notify.Ticket.t()}
  def notify_register(opts) when is_list(opts) do
    {server_opts, call_opts} = Keyword.split(opts, [:notify_server])

    Notify.Server.call({:register, call_opts}, server_opts)
  end

  @spec notify_unregister(reference() | Ticket.t(), notify_server_opts()) :: :ok
  def notify_unregister(ticket_or_ref, opts \\ [])

  def notify_unregister(%Ticket{ref: ref}, opts), do: notify_unregister(ref, opts)

  def notify_unregister(ref, opts)
      when is_reference(ref)
      when is_list(opts) do
    Notify.Server.call({:unregister, ref}, opts)
  end

  def off(name, opts \\ []) when is_binary(name) do
    {server_opts, rest} = Keyword.split(opts, [:names_server])
    %ExecCmd{name: name, cmd: "off", cmd_opts: rest} |> execute(server_opts)
  end

  def on(name, opts \\ []) when is_binary(name) do
    {server_opts, rest} = Keyword.split(opts, [:names_server])
    %ExecCmd{name: name, cmd: "on", cmd_opts: rest} |> execute(server_opts)
  end

  def status(name, opts \\ []) when is_binary(name) and is_list(opts) do
    names_lookup(name, opts) |> status_for_known_name(opts)
  end

  def toggle(name, opts \\ []) when is_binary(name) and is_list(opts) do
    case status(name, opts) do
      %ImmutableStatus{} -> %ExecResult{name: name, rc: :immutable}
      %MutableStatus{good?: false} -> %ExecResult{name: name, rc: :bad_status}
      %MutableStatus{pending?: true} -> %ExecResult{name: name, rc: :pending}
      %MutableStatus{cmd: "on"} -> off(name, opts)
      %MutableStatus{cmd: "off"} -> on(name, opts)
      %MutableStatus{cmd: cmd} -> %ExecResult{name: name, cmd: cmd, rc: :not_supported}
    end
  end

  defp callback_failure(%KnownName{} = kn, msg_parts) when is_list(msg_parts) do
    msg = Enum.join(msg_parts, "\n")

    Logger.error(msg)

    at = DateTime.utc_now()
    base = [name: kn.name, status_at: at, error: :callback_failed]

    if kn.mutable? do
      struct(MutableStatus, base)
    else
      struct(ImmutableStatus, base)
    end
  end

  defp ago_ms(%DateTime{} = dt) do
    DateTime.utc_now() |> DateTime.diff(dt, :millisecond)
  end

  defp status_for_known_name(%KnownName{valid?: true} = kn, opts) do
    type = if(kn.mutable?, do: :mut_status, else: :imm_status)

    case kn.callback do
      {:server, server} -> GenServer.call(server, {type, kn.name, opts})
      func when is_function(func) -> func.(type, kn.name, opts)
      {:module, mod} -> mod.status(type, kn.name, opts)
    end
  rescue
    error ->
      msg = [inspect(error), Exception.format_stacktrace()]
      callback_failure(kn, msg)
  catch
    kind, value ->
      msg = [inspect(kind), inspect(value, pretty: true), Exception.format_stacktrace()]
      callback_failure(kn, msg)
  end

  defp status_for_known_name(%KnownName{name: name}, _opts) do
    ImmutableStatus.not_found(name)
  end
end
