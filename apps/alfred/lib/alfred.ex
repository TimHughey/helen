defmodule Alfred do
  @moduledoc """
  Alfred - Master of devices
  """

  alias Alfred.{KnownName, NamesAgent, Notify}

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
      %KnownName{mod: mod, mutable: true} -> mod.execute(name, cmd_map, opts)
      %KnownName{mutable: false} -> {:failed, "#{in_quotes(name)} is immutable"}
      nil -> {:failed, "unknown: #{in_quotes(name)}"}
    end
  end

  def just_saw(%{states_rc: states_rc, device: {:ok, device}} = in_msg, mod) do
    {_rc, results} = states_rc
    seen = for %{schema: x} <- results, do: x

    %_{last_seen_at: seen_at} = device

    NamesAgent.just_saw(seen, seen_at, mod)

    in_msg
  end

  defdelegate known, to: NamesAgent
  defdelegate notify_register(name, opts), to: Notify, as: :register

  def off(name, opts \\ []) when is_binary(name) do
    %{cmd: "off", name: name, opts: opts} |> execute()
  end

  def on(name, opts \\ []) when is_binary(name) do
    %{cmd: "on", name: name, opts: opts} |> execute()
  end

  def status(name, opts \\ []) when is_binary(name) and is_list(opts) do
    case NamesAgent.get(name) do
      %KnownName{mod: mod} -> mod.status(name, opts)
      nil -> {:failed, "unknown: #{in_quotes(name)}"}
    end
  end

  defp in_quotes(name), do: "\"#{name}\""
end
