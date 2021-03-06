defmodule Sally.Command do
  @moduledoc false

  require Logger

  use Ecto.Schema
  require Ecto.Query
  alias Ecto.Query

  alias __MODULE__, as: Schema
  alias Sally.{DevAlias, Repo}

  schema "command" do
    field(:refid, :string)
    field(:cmd, :string, default: "unknown")
    field(:acked, :boolean, default: false)
    field(:orphaned, :boolean, default: false)
    field(:rt_latency_us, :integer, default: 0)
    field(:sent_at, :utc_datetime_usec)
    field(:acked_at, :utc_datetime_usec)

    belongs_to(:dev_alias, DevAlias)
  end

  def changeset(changes, %Schema{} = c) when is_map(changes) do
    alias Ecto.Changeset

    c
    |> Changeset.cast(changes, columns(:cast))
    |> Changeset.validate_required([:refid, :cmd, :sent_at, :dev_alias_id])
    # the cmd should be a minimum of two characters (e.g. "on")
    |> Changeset.validate_length(:cmd, min: 2, max: 32)
    |> Changeset.validate_length(:refid, is: 8)
    |> Changeset.unique_constraint(:refid)
  end

  # helpers for changeset columns
  def columns(:all) do
    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
  end

  def columns(:cast), do: columns(:all)

  # (1 of 2) ack via a schema id
  def ack_now(id, %DateTime{} = at) when is_integer(id), do: Repo.get(Schema, id) |> ack_now(:ack, at)

  # (2 of 3) ack via a schema
  def ack_now(%Schema{} = cmd_to_ack, disposition, at) when disposition in [:ack, :orphan] do
    # determine acked at here for updating the schema and calculating the rt_latency
    acked_at = cmd_to_ack.acked_at || at

    %{
      acked: true,
      acked_at: acked_at,
      orphaned: disposition == :orphan,
      rt_latency_us: DateTime.diff(acked_at, cmd_to_ack.sent_at, :microsecond)
    }
    |> changeset(cmd_to_ack)
    |> Repo.update!(returning: true)
  end

  def add(%DevAlias{} = da, cmd, opts) do
    new_cmd = Ecto.build_assoc(da, :cmds)

    [refid | _] = Ecto.UUID.generate() |> String.split("-")

    # grab the current time for sent_at and possibly acked_at (when ack: :immediate)
    utc_now = DateTime.utc_now()

    # handle special case of ack immediate
    ack_immediate? = opts[:ack] == :immediate
    acked_at = if ack_immediate?, do: utc_now, else: nil

    # base changes for all new cmds
    %{refid: refid, cmd: cmd, acked: ack_immediate?, acked_at: acked_at, sent_at: utc_now}
    |> changeset(new_cmd)
    |> Repo.insert!(returning: true)
  end

  def purge(%DevAlias{cmds: cmds}, :all, batch_size \\ 10) do
    all_ids = Enum.map(cmds, fn %Schema{id: id} -> id end)
    batches = Enum.chunk_every(all_ids, batch_size)

    for batch <- batches, reduce: {:ok, 0} do
      {:ok, acc} ->
        q = Query.from(c in Schema, where: c.id in ^batch)

        {deleted, _} = Repo.delete_all(q)

        {:ok, acc + deleted}
    end
  end

  def reported_cmd_changeset(%DevAlias{} = da, cmd, reported_at) do
    reported_cmd = Ecto.build_assoc(da, :cmds)

    [refid | _] = Ecto.UUID.generate() |> String.split("-")

    # grab the current time for sent_at and possibly acked_at (when ack: :immediate)
    utc_now = DateTime.utc_now()

    %{refid: refid, cmd: cmd, acked: true, orphan: false, acked_at: utc_now, sent_at: reported_at}
    |> changeset(reported_cmd)
  end
end
