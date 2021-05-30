defmodule Sally.PulseWidth.DB.Command do
  @moduledoc false

  require Logger

  use Ecto.Schema
  require Ecto.Query
  alias Ecto.Query

  alias Sally.PulseWidth.DB.Alias
  alias Sally.PulseWidth.DB.Command, as: Schema
  alias SallyRepo, as: Repo

  schema "pwm_cmd" do
    field(:refid, :string)
    field(:cmd, :string, default: "unknown")
    field(:acked, :boolean, default: false)
    field(:orphaned, :boolean, default: false)
    field(:rt_latency_us, :integer, default: 0)
    field(:sent_at, :utc_datetime_usec)
    field(:acked_at, :utc_datetime_usec)

    belongs_to(:alias, Alias)
  end

  def ack_now(%Schema{} = cmd_to_ack, disposition) when disposition in [:ack, :orphan] do
    # ensure we have an acked_at
    acked_at = cmd_to_ack.acked_at || DateTime.utc_now()

    %{
      acked: true,
      acked_at: acked_at,
      orphaned: disposition == :orphan,
      rt_latency_us: DateTime.diff(acked_at, cmd_to_ack.sent_at, :microsecond)
    }
    |> changeset(cmd_to_ack)
    |> Repo.update!(returning: true)
  end

  def add(%Alias{} = da, cmd, opts) do
    new_cmd = Ecto.build_assoc(da, :cmds)

    [refid | _] = Ecto.UUID.generate() |> String.split("-")

    # handle special case of ack immediate
    ack_immediate? = opts[:ack] == :immediate
    acked_at = if ack_immediate?, do: DateTime.utc_now(), else: nil

    # base changes for all new cmds
    %{refid: refid, cmd: cmd, acked: ack_immediate?, acked_at: acked_at, sent_at: DateTime.utc_now()}
    |> changeset(new_cmd)
    |> Repo.insert!(returning: true)
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

  defp changeset(changes, %Schema{} = c) when is_map(changes) do
    alias Ecto.Changeset

    c
    |> Changeset.cast(changes, columns(:cast))
    |> Changeset.validate_required([:refid, :cmd, :sent_at, :alias_id])
    # the cmd should be a minimum of two characters (e.g. "on")
    |> Changeset.validate_length(:cmd, min: 2, max: 32)
    |> Changeset.unique_constraint(:refid)
  end

  # helpers for changeset columns
  defp columns(:all) do
    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
  end

  defp columns(:cast), do: columns(:all)
end
