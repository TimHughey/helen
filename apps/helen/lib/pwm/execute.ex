defmodule PulseWidth.Execute do
  @moduledoc """
  PulseWidth Execute Implementation

  Consolidated API for issuing all commands to a PulseWidth device.

  This module consists of a series of execute functions that progressively
  validate the cmd to ultimately submit the cmd for execution.
  """

  require Logger

  alias PulseWidth.DB.Alias
  alias PulseWidth.Status

  @doc """
    Execute a command spec

    ### Options
      1. :lazy (boolean) - when true and status matches spec don't publish
      2. :force (boolean) - publish spec regardless of status
      2. :ignore_pending (boolean) - when true disregard pending status
      3. :ttl_ms (integer) - override Alias and Device ttl_ms
      4. :ack [:immediate, :host] - ack the spec immediately or wait for host ack
      5. :notify_when_released (boolean) - caller enters receive loop
      8. :notify_when_acked (boolean) - message is sent when acked

    ### Usage
      ```elixir

        map = %{cmd_map: %{pwm: "name", cmd: "on"}, opts: [lazy: false, ttl_ms: 1000]}
        execute(map)

        cmd_map = %{pwm: "name", cmd: off}
        execute(cmd_map, ignore_pending: true)

      ```
  """
  @doc since: "0.9.9"
  # (1 of 2) primary entry point
  def execute(status, name, cmd_map, opts) when is_map(status) do
    # default to lazy if not specified
    opts = if opts[:lazy] == false, do: opts, else: opts ++ [lazy: true]

    case validate_cmd_map(cmd_map) do
      :valid -> exec_cmd_map(name, status, cmd_map, opts)
      {:invalid, _} = rc -> rc
    end
  end

  # (11 of 11) execute the cmd!
  # opts can contain notify_when_released: true to enter a receive loop waiting for ack
  def execute(:execute, %Alias{} = a, cmd, opts) do
    Alias.record_cmd(a, cmd, opts) |> assemble_execute_rc()
  end

  defp assemble_execute_rc(x) do
    base = fn list -> [name: x.name] ++ list end
    current = fn cmd -> [cmd: cmd] |> base.() end
    fail_msg = fn msg, x -> [msg, ":\n", inspect(x, pretty: true)] |> IO.iodata_to_binary() end
    failed = fn msg, rc -> {:failed, [invalid: fail_msg.(msg, rc)] |> base.()} end
    pending = fn c, rc -> {:pending, [cmd: c.cmd, refid: c.refid, pub_rc: rc] |> base.()} end

    case x do
      # cmd inserted, alias updated. this was an immediate ack.
      %{cmd_rc: {:ok, _}, alias_rc: {:ok, a}} -> {:ok, a.cmd |> current.()}
      %{cmd_rc: {:ok, _}, alias_rc: rc} -> "alias update failed" |> failed.(rc)
      %{cmd_rc: {:ok, new_cmd}, pub_rc: {:ok, _} = pub_rc} -> new_cmd |> pending.(pub_rc)
      x -> "execute failed" |> failed.(x)
    end
  end

  defp exec_cmd_map(name, status, cmd_map, opts) when is_binary(name) do
    # default to lazy if not specified
    opts = Keyword.put_new(opts, :lazy, true)

    # force option takes precedence over lazy
    force = opts[:lazy] == false || opts[:force] == true

    # compare/3 returns:
    # 1. tuple when conditions do not support execute (e.g. invalid, ttl_expired, pending)
    # 2. single atom for actual comparison result
    case Status.compare(status, cmd_map, opts) do
      rc when rc == :not_equal or force -> exec_cmd_map(:now, name, cmd_map, opts)
      rc when rc == :equal -> {:ok, status}
      rc when is_tuple(rc) -> rc
    end
  end

  # (2 of 2)

  defp exec_cmd_map(:now, name, cmd, opts) do
    Alias.record_cmd(name, cmd, opts) |> assemble_execute_rc()
  end

  defp validate_cmd_map(%{name: _} = cmd_map) do
    case cmd_map do
      %{cmd: c} when c in ["on", "off"] -> :valid
      %{cmd: c, type: t} when is_binary(c) and is_binary(t) -> :valid
      %{cmd: c} when is_binary(c) -> {:invalid, "custom cmds must include :type"}
      _ -> {:invalid, "cmd map not recognized"}
    end
  end

  defp validate_cmd_map(_cmap), do: {:invalid, "must contain :name"}

  defp log(x) do
    #  ["\n", inspect(x, pretty: true), "\n"] |> Logger.info()
    x
  end
end
