defmodule Broom.DB.Command do
  @moduledoc false

  alias Ecto.Query
  require Query

  use Ecto.Schema

  alias __MODULE__, as: Schema
  alias Broom.DB.Alias

  schema "broom_cmd" do
    field(:refid, :string)
    field(:cmd, :string, default: "unknown")
    field(:acked, :boolean, default: false)
    field(:orphaned, :boolean, default: false)
    field(:rt_latency_us, :integer)
    field(:sent_at, :utc_datetime_usec)
    field(:acked_at, :utc_datetime_usec)

    belongs_to(:alias, Alias)

    timestamps(type: :utc_datetime_usec)
  end

  def ack_now(%Schema{} = cmd_to_ack, acked_at) do
    %{
      acked: true,
      acked_at: acked_at,
      rt_latency_us: DateTime.diff(acked_at, cmd_to_ack.sent_at, :microsecond)
    }
    |> changeset(cmd_to_ack)
    |> BroomRepo.update(returning: true)
    |> load_alias()
  end

  def ack_now(id_or_refid, acked_at) do
    clause = if is_integer(id_or_refid), do: [id: id_or_refid], else: [refid: id_or_refid]

    case BroomRepo.get_by(Schema, clause) do
      %Schema{} = c -> ack_now(c, acked_at)
      nil -> {:ok, "unknown id or refid: #{id_or_refid}"}
    end
  end

  def add(%Alias{} = a, %{cmd: cmd}, opts) do
    # associate the new command with the Alias
    new_cmd = Ecto.build_assoc(a, :cmds)
    ack_immediate? = opts[:ack] == :immediate

    # initial values for all new cmds including acked/acked_at when ack immediate is requested
    %{
      refid: Ecto.UUID.generate() |> String.split("-") |> hd(),
      sent_at: DateTime.utc_now(),
      cmd: cmd,
      acked: ack_immediate?,
      acked_at: if(ack_immediate?, do: DateTime.utc_now(), else: nil)
    }
    |> changeset(new_cmd)
    |> BroomRepo.insert(returning: true)
  end

  def load_alias(schema_or_tuple) do
    case schema_or_tuple do
      {:ok, %Schema{} = c} -> {:ok, BroomRepo.preload(c, [:alias])}
      %Schema{} = c -> BroomRepo.preload(c, [:alias])
      passthrough -> passthrough
    end
  end

  def orphan_now(%Schema{} = cmd_to_orphan) do
    %{orphaned: true, acked: true, acked_at: DateTime.utc_now()}
    |> changeset(cmd_to_orphan)
    |> BroomRepo.update(returning: true)
  end

  def orphan_now(cmd_id_to_orphan) do
    case BroomRepo.get(Schema, cmd_id_to_orphan) do
      %Schema{} = c -> orphan_now(c)
      nil -> {:not_found, "unknown cmd id: #{cmd_id_to_orphan}"}
    end
  end

  # (1 of 2) support pipeline where the change map is first arg
  defp changeset(changes, %Schema{} = c) when is_map(changes), do: changeset(c, changes)

  defp changeset(%Schema{} = c, changes) when is_map(changes) do
    alias Ecto.Changeset

    c
    |> Changeset.cast(changes, columns(:cast))
    |> Changeset.validate_required([:cmd, :sent_at, :alias_id])
    # the cmd should be a minimum of two characters (e.g. "on")
    |> Changeset.validate_length(:cmd, min: 2, max: 32)
    |> Changeset.unique_constraint(:refid)
  end

  # helpers for changeset columns
  defp columns(:all) do
    these_cols =
      [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
  end

  defp columns(:cast), do: columns(:all)
end
