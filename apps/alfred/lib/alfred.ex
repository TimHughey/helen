defmodule Alfred do
  require Logger

  @moduledoc """
  Alfred - Master of devices
  """

  alias Alfred.{ExecCmd, ExecResult, ImmutableStatus, KnownName, MutableStatus, Names, Notify}

  # is a name available (aka unknown)
  def available(name), do: not Names.exists?(name)

  defdelegate delete(name), to: Names

  def execute(name, opts) when is_binary(name) and is_list(opts) do
    default = %ExecCmd{}

    %ExecCmd{
      name: name,
      cmd: opts[:cmd],
      cmd_params: opts[:params] || default.cmd_params,
      cmd_opts: opts[:cmd_opts] || default.cmd_opts,
      pub_opts: opts[:pub_opts] || default.pub_opts
    }
    |> execute()
  end

  def execute(%ExecCmd{} = ec) do
    case Names.lookup(ec.name) do
      nil -> %ExecResult{name: ec.name, cmd: ec.cmd, rc: :not_found}
      %KnownName{callback_mod: cb_mod, mutable?: true} -> cb_mod.execute(ec)
      %KnownName{mutable?: false} -> %ExecResult{name: ec.name, cmd: ec.cmd, rc: :immutable}
    end
  end

  defdelegate is_name_known?(name), to: Names, as: :exists?
  defdelegate just_saw(js), to: Names
  defdelegate just_saw_cast(js), to: Names

  def known_names(what \\ :names) do
    for %KnownName{} = kn <- Names.all_known() do
      case what do
        :details -> kn
        :names -> kn.name
        :seen_ago -> {kn.name, DateTime.utc_now() |> DateTime.diff(kn.seen_at, :millisecond)}
        :seen_at -> {kn.name, kn.seen_at}
        _ -> {:opts, [:details, :names, :seen_ago, :seen_at]}
      end
    end
  end

  defdelegate notify_register(name, opts \\ []), to: Notify, as: :register
  defdelegate notify_unregister(notify_to), to: Notify, as: :unregister

  def off(name, opts \\ []) when is_binary(name) do
    %ExecCmd{name: name, cmd: "off", cmd_opts: opts} |> execute()
  end

  def on(name, opts \\ []) when is_binary(name) do
    %ExecCmd{name: name, cmd: "on", cmd_opts: opts} |> execute()
  end

  def status(name, opts \\ [])

  def status(name, opts) when is_binary(name) and is_list(opts) do
    case Names.lookup(name) do
      %KnownName{callback_mod: cb_mod, mutable?: true} -> cb_mod.status(:mutable, name, opts)
      %KnownName{callback_mod: cb_mod, mutable?: false} -> cb_mod.status(:immutable, name, opts)
      nil -> {:failed, "unknown: #{name}"}
    end
  end

  def toggle(name, opts \\ []) when is_binary(name) and is_list(opts) do
    case status(name, opts) do
      %MutableStatus{pending?: true} -> {:failed, "pending command"}
      %MutableStatus{cmd: "on"} -> off(name, opts)
      %MutableStatus{cmd: "off"} -> on(name, opts)
      %MutableStatus{cmd: cmd} -> {:failed, "can not toggle: #{cmd}"}
      %ImmutableStatus{} -> {:failed, "can not toggle immutable"}
    end
  end
end
