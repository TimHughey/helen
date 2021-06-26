defmodule Alfred do
  require Logger

  @moduledoc """
  Alfred - Master of devices
  """

  alias Alfred.{ExecCmd, KnownName, MutableStatus, Names, Notify}

  # is a name available (aka unknown)
  defdelegate available(name), to: Names, as: :exists?
  defdelegate delete(name), to: Names

  def execute(%ExecCmd{} = ec) do
    case Names.lookup(ec.name) do
      %KnownName{callback_mod: cb_mod, mutable?: true} -> cb_mod.execute(ec)
      %KnownName{mutable?: false} -> {:failed, "immutable: #{ec.name}"}
      %KnownName{name: "unknown"} -> {:failed, "unknown: #{ec.name}"}
    end
  end

  defdelegate is_name_known?(name), to: Names, as: :exists?
  defdelegate just_saw(js), to: Names
  defdelegate just_saw_cast(js), to: Names

  defdelegate notify_register(name, opts \\ []), to: Notify, as: :register
  defdelegate notify_unregister(notify_to), to: Notify, as: :unregister

  def off(name, opts \\ []) when is_binary(name) do
    %ExecCmd{name: name, cmd: "off", cmd_opts: opts} |> execute()
  end

  def on(name, opts \\ []) when is_binary(name) do
    %ExecCmd{name: name, cmd: "on", cmd_opts: opts} |> execute()
  end

  def status(name, opts \\ []) when is_binary(name) and is_list(opts) do
    case Names.lookup(name) do
      %KnownName{callback_mod: cb_mod} -> cb_mod.status(name, opts)
      %KnownName{name: "unknown"} -> {:failed, "unknown: #{name}"}
    end
  end

  def toggle(name, opts \\ []) when is_binary(name) and is_list(opts) do
    case status(name, opts) do
      %MutableStatus{pending?: true} -> {:failed, "pending command"}
      %MutableStatus{cmd: "on"} -> off(name, opts)
      %MutableStatus{cmd: "off"} -> on(name, opts)
      %MutableStatus{cmd: cmd} -> {:failed, "can not toggle: #{cmd}"}
    end
  end
end
