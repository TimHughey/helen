defmodule PulseWidth.DB.Command do
  @moduledoc false

  use Ecto.Schema

  require Ecto.Query
  alias Ecto.Query

  alias Alfred.ExecCmd
  alias PulseWidth.DB.Alias
  alias PulseWidth.DB.Command, as: Schema

  schema "pwm_cmd" do
    field(:refid, Ecto.UUID, autogenerate: true)
    field(:cmd, :string, default: "unknown")
    field(:acked, :boolean, default: false)
    field(:orphaned, :boolean, default: false)
    field(:rt_latency_us, :integer, default: 0)
    field(:sent_at, :utc_datetime_usec)
    field(:acked_at, :utc_datetime_usec)

    belongs_to(:alias, Alias, source: :alias_id, references: :id, foreign_key: :alias_id)

    timestamps(type: :utc_datetime_usec)
  end

  def ack_now(refid, acked_at) do
    case Repo.get_by(Schema, refid: refid) |> Repo.preload([:alias]) do
      %Schema{sent_at: sent_at} = cmd_to_ack ->
        latency = DateTime.diff(acked_at, sent_at, :microsecond)
        now = DateTime.utc_now()

        cmd_to_ack
        |> changeset(%{acked: true, acked_at: now, rt_latency_us: latency})
        |> Repo.update(returning: true)

      {:error, e} ->
        {:failed, "unable to find refid: #{inspect(e)}"}

      # allow receipt of refid ack messages while passively processing the rpt topic
      # (e.g. testing by attaching to production reporting topic)
      nil ->
        {:ok, "unknown refid: #{refid}"}
    end
  end

  def add(%Alias{} = a, %ExecCmd{cmd: cmd}, opts) do
    # associate the new command with the Alias
    new_cmd = Ecto.build_assoc(a, :cmds)

    # base changes for all new cmds
    %{sent_at: DateTime.utc_now(), cmd: cmd}
    |> ack_immediate_if_requested(opts[:ack] == :immediate)
    |> changeset(new_cmd)
    |> Repo.insert(returning: true)
  end

  def add(%Alias{} = a, %{cmd: cmd}, opts) do
    # associate the new command with the Alias
    new_cmd = Ecto.build_assoc(a, :cmds)

    # base changes for all new cmds
    %{sent_at: DateTime.utc_now(), cmd: cmd}
    |> ack_immediate_if_requested(opts[:ack] == :immediate)
    |> changeset(new_cmd)
    |> Repo.insert(returning: true)
  end

  # (1 of 2) support pipeline where the change map is first arg
  def changeset(changes, %Schema{} = c) when is_map(changes), do: changeset(c, changes)

  def changeset(%Schema{} = c, changes) when is_map(changes) do
    alias Ecto.Changeset

    c
    |> Changeset.cast(changes, columns(:cast))
    |> Changeset.validate_required([:cmd, :sent_at, :alias_id])
    # the cmd should be a minimum of two characters (e.g. "on")
    |> Changeset.validate_length(:cmd, min: 2, max: 32)
    |> Changeset.unique_constraint(:refid)
  end

  # helpers for changeset columns
  def columns(:all) do
    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
  end

  def columns(:cast), do: columns(:all)

  def orphan_now(%Schema{} = c) do
    changeset(c, %{orphaned: true, acked: true, acked_at: DateTime.utc_now()}) |> Repo.update(returning: true)
  end

  def purge(%Alias{cmds: cmds}, :all) do
    all_ids = Enum.map(cmds, fn %Schema{id: id} -> id end)
    batches = Enum.chunk_every(all_ids, 10)

    for batch <- batches, reduce: {:ok, 0} do
      {:ok, acc} ->
        q = Query.from(c in Schema, where: c.id in ^batch)

        {deleted, _} = Repo.delete_all(q)

        {:ok, acc + deleted}
    end
  end

  def put_status(m, status), do: put_in(m, [:cmd_last], status)

  # (1 of 5) received an empty list
  def status(m, []), do: put_status(m, %{cmd: "unknown"})

  # ( 1 of 5) received a list of cmds grab the first one
  def status(m, cmds) when is_list(cmds), do: status(m, hd(cmds))

  # (2 of 5) acked cmd
  def status(m, %Schema{acked: true, orphaned: false} = c) when is_map(m) do
    put_status(m, %{cmd: c.cmd, acked: true, acked_at: c.acked_at, rt_latency_us: c.rt_latency_us})
  end

  # (3 of 5) pending
  def status(m, %Schema{acked: false} = c) when is_map(m) do
    put_status(m, %{cmd: c.cmd, pending: true, at: c.acked_at, refid: c.refid})
  end

  # (4 of 5) orphaned
  def status(m, %Schema{orphaned: true} = c) do
    put_status(m, %{cmd: "unknown", orphaned: true, orphaned_at: c.acked_at})
  end

  # (5 of 5)
  def status(m, _) do
    put_status(m, %{cmd: "unknown", invalid: true, at: DateTime.utc_now()})
  end

  # (1 of 2) ack immediate is requested, merge in the appropriate changes
  defp ack_immediate_if_requested(changes, true) do
    Map.merge(changes, %{acked: true, orphaned: false, acked_at: changes.sent_at})
  end

  # (2 of 2) nothing to see here
  defp ack_immediate_if_requested(changes, _), do: changes
end
