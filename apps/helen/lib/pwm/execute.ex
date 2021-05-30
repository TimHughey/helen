defmodule PulseWidth.Execute do
  @moduledoc """
  PulseWidth Execute Implementation

  Consolidated API for issuing all commands to a PulseWidth device.

  This module consists of a series of execute functions that progressively
  validate the cmd to ultimately submit the cmd for execution.
  """

  require Logger

  alias Alfred.{ExecCmd, ExecResult}
  alias PulseWidth.DB.{Alias, Command, Device}
  alias PulseWidth.Status

  use Broom,
    schema: Command,
    metrics_interval: "PT1M",
    track_timeout: "PT13S",
    purge_interval: "PT1H",
    purge_older_than: "PT1D",
    restart: :permanent,
    shutdown: 1000

  # NOTE:
  # original msg is augmented with ack results and returned for downstream processing
  def ack_if_needed(%{cmdack: true, refid: refid, device: {:ok, %Device{}} = dev_rc} = msg) do
    alias PulseWidth.Command.Fact

    # prepare the msg map for the results
    msg_out = Map.drop(msg, [:cmdack, :refid]) |> Map.merge(%{cmd_rc: nil, broom_rc: nil, metric_rc: nil})

    case Command.ack_now(refid, msg.msg_recv_dt) do
      {:ok, %Command{}} = cmd_rc ->
        %{
          msg_out
          | cmd_rc: cmd_rc,
            broom_rc: Broom.release(cmd_rc),
            metric_rc: Fact.write_metric(cmd_rc, dev_rc, msg.msg_recv_dt)
        }

      {:error, e} ->
        %{msg_out | cmd_rc: {:failed, "unable to find refid: #{inspect(e)}"}}

      # allow receipt of refid ack messages while passively processing the rpt topic
      # (e.g. testing by attaching to production reporting topic)
      nil ->
        %{msg_out | cmd_rc: {:ok, "unknown refid: #{refid}"}}
    end
  end

  def ack_if_needed(msg), do: put_in(msg, [:cmd_rc], {:ok, "ignored, not a cmdack"})

  @spec execute(ExecCmd.t()) :: ExecResult.t()
  def execute(%ExecCmd{force: true} = ec) do
    Alias.find(ec.name) |> exec_cmd()
  end

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
  # NOTE: refactor of all execute code into this module
  def execute(cmd_map) when is_map(cmd_map) do
    case cmd_map do
      %{name: _} -> execute(Map.delete(cmd_map, :opts), cmd_map[:opts] || [])
      _x -> {:invalid, "cmd map must include name"}
    end
  end

  # NOTE: refactor of all execute code into this module
  def execute(cmd_map, opts) when is_map(cmd_map) and is_list(opts) do
    Repo.transaction(fn ->
      cmd_map.name
      |> Alias.find()
      |> Status.make_status(opts)
      |> execute(cmd_map, opts)
    end)
    |> elem(1)
  end

  ##
  ##
  ## INCOMPLETE!!!
  ##
  ##

  # NOTE: OLD
  def execute(status, cmd_map, opts) when is_map(status) do
    # default to lazy if not specified
    opts = if opts[:lazy] == false, do: opts, else: opts ++ [lazy: true]

    case validate_cmd_map(cmd_map) do
      :valid -> exec_cmd_map(status, cmd_map, opts)
      {:invalid, _} = rc -> rc
    end
  end

  def track_stats(action, keys) do
    case {action, keys} do
      {:get, _} -> Broom.counts()
      {:reset, x} when is_list(x) -> Broom.counts_reset(x)
    end
  end

  @impl true
  def track_timeout(%Broom.TrackerEntry{schema_id: id}) do
    Repo.transaction(fn ->
      cmd_schema = Repo.get(Command, id)

      case cmd_schema do
        %Command{acked: true} = c -> c
        %Command{acked: false} = c -> Command.orphan_now(c)
      end
    end)
    |> elem(1)
  end

  defp assemble_execute_rc(x) do
    base = fn list -> [name: x.name] ++ list end
    current = fn cmd -> [cmd: cmd] |> base.() end
    fail_msg = fn msg, x -> [msg, ":\n", inspect(x, pretty: true)] |> IO.iodata_to_binary() end
    failed = fn msg, rc -> {:failed, [invalid: fail_msg.(msg, rc)] |> base.()} end
    pending = fn c, rc -> {:pending, [cmd: c.cmd, refid: c.refid, pub_rc: rc] |> base.()} end

    out = fn x ->
      Logger.debug(["\n", inspect(x, pretty: true), "\n"])
      x
    end

    case x do
      # cmd inserted, alias updated. this was an immediate ack.
      %{cmd_rc: {:ok, _}, alias_rc: {:ok, a}} -> {:ok, a.cmd |> current.()}
      %{cmd_rc: {:ok, _}, alias_rc: rc} -> "alias update failed" |> failed.(rc)
      %{cmd_rc: {:ok, new_cmd}, pub_rc: {:ok, _} = pub_rc} -> new_cmd |> pending.(pub_rc)
      x -> "execute failed" |> failed.(x)
    end
    |> out.()
  end

  defp exec_cmd(%Alias{}) do
  end

  # (1 of 2) determine if a cmd must be sent
  defp exec_cmd_map(status, cmd_map, opts) when is_map(status) do
    # default to lazy if not specified
    opts = Keyword.put_new(opts, :lazy, true)

    # force option takes precedence over lazy
    force = opts[:lazy] == false || opts[:force] == true

    # compare/3 returns:
    # 1. tuple when conditions do not support execute (e.g. invalid, ttl_expired, pending)
    # 2. single atom for actual comparison result
    case Status.compare(status, cmd_map, opts) do
      rc when rc == :not_equal or force -> exec_cmd_map(:now, cmd_map, opts)
      rc when rc == :equal -> {:ok, status}
      rc when is_tuple(rc) -> rc
    end
  end

  # (2 of 2)
  defp exec_cmd_map(:now, cmd_map, opts) do
    alias PulseWidth.Payload

    Logger.debug(["\n", inspect(cmd_map, pretty: true), "\n", inspect(opts, pretty: true)])

    # NOTE: Alias.find/1 returns an Alias or nil
    found_alias = Alias.find(cmd_map.name)
    cmd_rc = Command.add(found_alias, cmd_map, opts)
    broom_rc = Broom.track(cmd_rc, opts)

    # NOTE: handle_ack_immediate_if_needed/2 returns a tuple
    alias_rc = handle_ack_immediate_if_needed(found_alias, cmd_rc)

    Repo.checkout(fn ->
      Repo.transaction(fn ->
        %{
          name: found_alias.name,
          alias_rc: alias_rc,
          cmd_rc: cmd_rc,
          broom_rc: broom_rc,
          pub_rc: Payload.send_cmd(found_alias, cmd_map, make_pub_opts(cmd_rc, opts))
        }
        |> assemble_execute_rc()
      end)
    end)
    |> elem(1)
  end

  defp handle_ack_immediate_if_needed(%Alias{} = a, cmd_rc) do
    # reflect the acked cmd in the Alias (returns an :ok tuple)
    # otherwise normalize the found alias into an :ok tuple
    case cmd_rc do
      {:ok, %Command{acked: true, cmd: acked_cmd}} -> Alias.update_cmd(a, acked_cmd)
      _ -> {:ok, a}
    end
  end

  def make_pub_opts(cmd_rc, opts) do
    case cmd_rc do
      {:ok, %Command{} = c} -> [refid: c.refid] ++ [opts]
      _ -> opts
    end
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
end
