defmodule Broom.DB.Command do
  @moduledoc false

  alias Ecto.Query
  require Query

  use Ecto.Schema

  alias __MODULE__, as: Schema
  alias Broom.DB.DevAlias
  alias BroomRepo, as: Repo

  schema "broom_cmd" do
    field(:refid, :string)
    field(:cmd, :string, default: "unknown")
    field(:acked, :boolean, default: false)
    field(:orphaned, :boolean, default: false)
    field(:rt_latency_us, :integer)
    field(:sent_at, :utc_datetime_usec)
    field(:acked_at, :utc_datetime_usec)

    belongs_to(:dev_alias, DevAlias)

    timestamps(type: :utc_datetime_usec)
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

  def add(%DevAlias{} = a, %{cmd: cmd}, opts) do
    # associate the new command with the DevAlias
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

  # (1 of 2) support pipeline where the change map is first arg
  defp changeset(changes, %Schema{} = cmd_schema) do
    alias Ecto.Changeset

    cmd_schema
    |> Changeset.cast(changes, columns(:cast))
    |> Changeset.validate_required([:cmd, :sent_at, :dev_alias_id])
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
