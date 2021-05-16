defmodule Alfred do
  @moduledoc """
  Alfred - Master of devices
  """

  alias Alfred.{KnownName, NamesAgent, Notify}

  # is a name available (aka unknown)
  def available(name) do
    case is_name_known?(name) do
      false -> {:alfred, :available, name}
      true -> {:alfred, :taken, NamesAgent.get(name)}
    end
  end

  defdelegate delete(name), to: NamesAgent

  # (1 of 2) accept a single arg, ensure it contains name and extract opts if needed
  def execute(cmd_map) when is_map(cmd_map) do
    case cmd_map do
      %{name: name, opts: opts} = x -> execute(name, Map.delete(x, :opts), opts)
      %{name: name} = x -> execute(name, x, [])
      _x -> {:invalid, "execute map must include name"}
    end
  end

  # (2 of 2) name, cmd_map and opts specified as unique arguments
  # NOTE: opts can contain notify_when_released: true to enter a receive loop waiting for ack
  def execute(name, cmd_map, opts) when is_binary(name) and is_map(cmd_map) and is_list(opts) do
    case NamesAgent.get(name) do
      %KnownName{callback_mod: cb_mod, mutable: true} -> cb_mod.execute(name, cmd_map, opts)
      %KnownName{mutable: false} -> {:failed, "#{in_quotes(name)} is immutable"}
      nil -> {:failed, "unknown: #{in_quotes(name)}"}
    end
  end

  defdelegate is_name_known?(name), to: NamesAgent, as: :exists?

  # (1 of 2) process seen names from the inbound msg pipeline
  def just_saw(in_msg) do
    put_rc = fn x -> put_in(in_msg, [:alfred_rc], x) end

    in_msg
    |> get_seen_names_from_in_msg()
    |> make_seen_list()
    |> NamesAgent.just_saw()
    |> put_rc.()
    |> log_and_passthrough("just_saw:")
  end

  defdelegate known(), to: NamesAgent
  defdelegate notify_register(name, opts), to: Notify, as: :register

  def off(name, opts \\ []) when is_binary(name) do
    %{cmd: "off", name: name, opts: opts} |> execute()
  end

  def on(name, opts \\ []) when is_binary(name) do
    %{cmd: "on", name: name, opts: opts} |> execute()
  end

  def status(name, opts \\ []) when is_binary(name) and is_list(opts) do
    case NamesAgent.get(name) do
      %KnownName{callback_mod: cb_mod} -> cb_mod.status(name, opts)
      nil -> {:failed, "unknown: #{in_quotes(name)}"}
    end
  end

  defp get_seen_names_from_in_msg(in_msg) do
    case in_msg do
      %{states_rc: {:ok, x}} -> x
      %{datapoints_rc: {:ok, x}} -> x
      _x -> {:failed, "unable to determine seen list"}
    end
  end

  defp log_and_passthrough(what, msg) do
    require Logger
    [msg, "\n", inspect(what, pretty: true), "\n"] |> Logger.debug()

    what
  end

  defp make_seen_list(results) do
    case results do
      [%_{} | _] = schemas -> for %{schema: x, success: true} <- schemas, do: x
      previous_rc -> previous_rc
    end
  end

  defp in_quotes(name), do: "\"#{name}\""
end
