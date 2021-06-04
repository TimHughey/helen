defmodule Sally.PulseWidth.Execute do
  require Logger

  alias Alfred.ExecCmd
  alias Alfred.ExecResult
  alias Alfred.MutableStatus, as: MutStatus
  alias Broom.TrackerEntry
  alias Sally.PulseWidth.DB.{Alias, Command}
  alias Sally.PulseWidth.Payload
  alias Sally.PulseWidth.Status
  alias Sally.Repo

  use Broom,
    schema: Command,
    metrics_interval: "PT1M",
    track_timeout: "PT13S",
    purge_interval: "PT1H",
    purge_older_than: "PT1D",
    restart: :permanent,
    shutdown: 1000

  def ack_now(refid, at) do
    Repo.transaction(fn ->
      Repo.checkout(fn ->
        case Broom.get_refid_tracker_entry(refid) do
          %TrackerEntry{} = te ->
            Alias.update_cmd(te.alias_id, te.cmd)
            Command.ack_now(te.schema_id, at) |> Broom.release()

          _ ->
            nil
        end
      end)
    end)
  end

  def cmd(%ExecCmd{} = ec) do
    # NOTE!
    #
    # 1. Broom.track/2 must be invoked outside the cmd insert to ensure the command is available
    #    when immediate ack is requested
    #
    # 2. insert_cmd_if_needed/1 *MUST* preload the dev alias and device for downstream

    with %ExecCmd{valid?: true} = ec <- ExecCmd.validate(ec),
         {:ok, %ExecCmd{inserted_cmd: %Command{}} = ec} <- insert_cmd_if_needed(ec),
         {:ok, %TrackerEntry{} = te} <- Broom.track(ec.inserted_cmd, ec.cmd_opts) do
      # everything is in order, send the command to the remote host
      %ExecCmd{ec | pub_ref: Payload.send_cmd(ec)} |> ExecResult.ok(te)
    else
      %ExecCmd{valid?: false} = x -> ExecResult.invalid(x)
      {:ok, :no_change} -> ExecResult.no_change(ec)
      {:ok, %MutStatus{} = x} -> ExecResult.from_status(x)
      {:error, _} = rc -> ExecResult.error(ec.name, rc)
    end
  end

  @impl true
  def track_timeout(%Broom.TrackerEntry{} = te) do
    Repo.transaction(fn ->
      Repo.checkout(fn ->
        # the command was already acked when it was tracked so reflect it in the Alias
        if te.acked, do: Alias.update_cmd(te.alias_id, te.cmd)

        case Repo.get!(Command, te.schema_id) do
          %Command{acked: false} = c -> Command.ack_now(c, :orphan, DateTime.utc_now())
          %Command{acked: true} = c -> c
        end
        |> Repo.preload(alias: [:device])
      end)
    end)
    |> elem(1)
  end

  defp insert_cmd_if_needed(%ExecCmd{} = ec) do
    Repo.transaction(fn ->
      Repo.checkout(fn ->
        {status_opts, cmd_opts_rest} = Keyword.split(ec.cmd_opts, [:ttl_ms])
        status_opts = [need_dev_alias: true] ++ status_opts
        force = cmd_opts_rest[:force] || false

        with {dev_alias, status} <- Status.get(ec.name, status_opts),
             %MutStatus{found?: true, ttl_expired?: false} <- status,
             {:add_cmd, true} <- {:add_cmd, force or ec.cmd != status.cmd} do
          # actual command to dev alias is required
          # NOTE! preload the dev_alias and device for downstream
          x = Command.add(dev_alias, ec.cmd, ec.cmd_opts) |> Repo.preload(alias: [:device])
          %ExecCmd{ec | inserted_cmd: x, cmd_opts: cmd_opts_rest}
        else
          %MutStatus{} = x -> x
          {:add_cmd, false} -> :no_change
        end
      end)
    end)
  end
end
