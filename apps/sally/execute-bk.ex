defmodule Sally.PulseWidth.Execute do
  require Logger

  alias Alfred.ExecCmd, as: Cmd
  alias Alfred.ExecResult, as: Result
  alias Alfred.MutableStatus, as: MutStatus
  alias Sally.MsgOut
  alias Sally.PulseWidth.DB.{Alias, Command}
  alias Sally.PulseWidth.Status
  alias SallyRepo, as: Repo

  use Broom,
    schema: Command,
    metrics_interval: "PT1M",
    track_timeout: "PT13S",
    purge_interval: "PT1H",
    purge_older_than: "PT1D",
    restart: :permanent,
    shutdown: 1000

  def cmd(%Cmd{} = ec) do
    Repo.transaction(fn ->
      Repo.checkout(fn ->
        with %Cmd{valid?: true} = ec_validated <- validate_cmd(ec),
             %Cmd{status: status} = ec_with_status <- get_status(ec_validated),
             %MutStatus{found?: true, ttl_expired?: false} <- status do
          ec_with_status |> exec_cmd_if_needed()
        else
          %Cmd{valid?: false} = ec -> Result.invalid(ec.name, ec.invalid_reason)
          %MutStatus{ttl_expired?: true, status_at: at} -> Result.ttl_expired(ec.name, at)
          %MutStatus{found?: false} -> Result.not_found(ec.name)
        end
      end)
    end)
    # pass the original ExecCmd for use if the txn fails
    |> assemble_response(ec)
  end

  @impl true
  def track_timeout(%Broom.TrackerEntry{} = te) do
    Repo.transaction(fn ->
      Repo.checkout(fn ->
        # the command was already acked when it was tracked so reflect it in the Alias
        if te.acked, do: Alias.update_cmd(te.alias_id, te.cmd)

        case Repo.get!(Command, te.schema_id) do
          %Command{acked: false} = c -> Command.ack_now(c, :orphan)
          %Command{acked: true} = c -> c
        end
        |> Repo.preload(alias: [:device])
      end)
    end)
    |> elem(1)
  end

  defp assemble_response(txn_rc, %Cmd{} = original_ec) do
    Logger.debug(inspect(txn_rc, pretty: true))

    case txn_rc do
      {:ok, %Result{} = er} -> er
      {:error, _} = rc -> %Result{name: original_ec.name, rc: rc}
    end
  end

  defp exec_cmd_if_needed(%Cmd{} = ec) do
    force = ec.cmd_opts[:force] || false

    if force or ec.cmd != ec.status.cmd do
      added_cmd = Command.add(ec.dev_alias, ec.cmd, ec.cmd_opts)
      %Cmd{ec | added_cmd: added_cmd} |> track_cmd() |> send_cmd()
    else
      %Result{name: ec.name, rc: :ok, cmd: ec.status.cmd}
    end
  end

  defp get_status(%Cmd{} = ec) do
    {status_opts, cmd_opts_rest} = Keyword.split(ec.cmd_opts, [:ttl_ms])

    status_opts = [need_dev_alias: true] ++ status_opts

    {dev_alias, status} = Status.get(ec.name, status_opts)
    Logger.debug("#{inspect(status_opts)}\n#{inspect(status, pretty: true)}")

    %Cmd{ec | status: status, dev_alias: dev_alias, cmd_opts: cmd_opts_rest}
  end

  defp make_result_from_tracker_entry(%Cmd{} = ec, %TrackerEntry{} = te) do
    %Result{
      name: ec.name,
      rc: :ok,
      refid: te.refid,
      track_timeout_ms: te.track_timeout_ms,
      will_notify_when_released: if(te.notify_pid |> is_pid(), do: true, else: false),
      cmd: te.cmd
    }
  end

  defp make_payload_data(%Cmd{cmd: cmd, cmd_params: p}) when map_size(p) > 0 do
    %{cmd: cmd} |> Map.merge(p)
  end

  defp make_payload_data(%Cmd{cmd: cmd}), do: %{cmd: cmd}

  defp send_cmd({%Cmd{} = ec, %Result{} = result}) do
    device = ec.dev_alias.device

    %MsgOut{host: device.host, device: device.ident, data: make_payload_data(ec)}
    |> MsgOut.apply_opts(ec.pub_opts)
    |> inspect(pretty: true)
    |> Logger.info()

    result
  end

  defp track_cmd(%Cmd{} = ec) do
    Logger.debug(inspect(ec, pretty: true))

    # return a tuple of the Cmd and the assembled Result for downstream
    case Broom.track(ec.added_cmd, ec.cmd_opts) do
      {:ok, %TrackerEntry{} = te} -> {ec, make_result_from_tracker_entry(ec, te)}
      {:error, _e} = rc -> {ec, %Result{name: ec.name, rc: rc}}
    end
  end

  defp validate_cmd(%Cmd{} = ec) do
    case ec do
      %Cmd{cmd: c} when c in ["on", "off"] -> %Cmd{ec | valid?: true}
      %Cmd{cmd: c, cmd_params: %{type: t}} when is_binary(c) and is_binary(t) -> %Cmd{ec | valid?: true}
      %Cmd{cmd: c} when is_binary(c) -> %Cmd{ec | invalid_reason: "custom cmds must include type"}
      _ -> %Cmd{ec | invalid_reason: "cmd must be a binary"}
    end
  end
end
