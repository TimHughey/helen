defmodule Sally.Command do
  @moduledoc false

  require Logger

  use Ecto.Schema
  # require Ecto.Query
  # alias Ecto.Query
  # mport Ecto.Query, only: [from: 2]

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

  def ack_now_cs(id, %DateTime{} = sent_at, %DateTime{} = ack_at, disposition) when is_atom(disposition) do
    alias Ecto.Changeset

    rt_us = DateTime.diff(ack_at, sent_at, :microsecond)
    changes = %{acked: true, acked_at: ack_at, orphaned: disposition == :orphan, rt_latency_us: rt_us}

    %Schema{id: id} |> Changeset.cast(changes, Map.keys(changes))
  end

  def add(%DevAlias{} = da, cmd, opts) do
    new_cmd = Ecto.build_assoc(da, :cmds)

    [refid | _] = Ecto.UUID.generate() |> String.split("-")

    # grab the current time for sent_at and possibly acked_at (when ack: :immediate)
    sent_at = opts[:sent_at] || DateTime.utc_now()

    # handle special case of ack immediate
    ack_immediate? = opts[:ack] == :immediate
    acked_at = if ack_immediate?, do: sent_at, else: nil

    # base changes for all new cmds
    %{refid: refid, cmd: cmd, acked: ack_immediate?, acked_at: acked_at, sent_at: sent_at}
    |> changeset(new_cmd)
    |> Repo.insert!(returning: true)
  end

  def load(id) when is_integer(id) do
    case Repo.get(Schema, id) do
      %Schema{} = x -> {:ok, x}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Load the `Sally.DevAlias`, if needed
  """
  @doc since: "0.5.15"
  def load_dev_alias(cmd) when is_struct(cmd) or is_nil(cmd) do
    cmd |> Repo.preload(:dev_alias)
  end

  def purge(%DevAlias{cmds: cmds}, :all, batch_size \\ 10) do
    import Ecto.Query, only: [from: 2]

    all_ids = Enum.map(cmds, fn %Schema{id: id} -> id end)
    batches = Enum.chunk_every(all_ids, batch_size)

    for batch <- batches, reduce: {:ok, 0} do
      {:ok, acc} ->
        q = from(c in Schema, where: c.id in ^batch)

        {deleted, _} = Repo.delete_all(q)

        {:ok, acc + deleted}
    end
  end

  def query_preload_latest_cmd(dev_alias_id) do
    import Ecto.Query, only: [from: 2]

    from(c in Schema,
      distinct: c.dev_alias_id,
      order_by: [desc: c.sent_at],
      where: [dev_alias_id: ^dev_alias_id]
    )
  end

  def query_preload_latest_cmd do
    import Ecto.Query, only: [from: 2]

    from(c in Schema, distinct: c.dev_alias_id, order_by: [desc: c.sent_at])
  end

  def reported_cmd_changeset(%DevAlias{} = da, cmd, reported_at) do
    reported_cmd = Ecto.build_assoc(da, :cmds)

    [refid | _] = Ecto.UUID.generate() |> String.split("-")

    # grab the current time for sent_at and possibly acked_at (when ack: :immediate)
    utc_now = DateTime.utc_now()

    %{refid: refid, cmd: cmd, acked: true, orphan: false, acked_at: utc_now, sent_at: reported_at}
    |> changeset(reported_cmd)
  end

  def summary(%Schema{} = x) do
    Map.take(x, [:cmd, :acked, :sent_at])
  end

  def summary([%Schema{} = x | _]), do: summary(x)

  def summary([]), do: %{}
end
