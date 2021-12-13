defmodule Broom.Host do
  @moduledoc false
  require Logger

  use Ecto.Schema
  require Ecto.Query

  alias Ecto.Query

  alias Broom.Host, as: Schema
  alias Broom.Repo

  schema "host" do
    field(:ident, :string)
    field(:name, :string)
    field(:profile, :string, default: "generic")
    field(:authorized, :boolean, default: true)
    field(:firmware_vsn, :string)
    field(:idf_vsn, :string)
    field(:app_sha, :string)
    field(:build_at, :utc_datetime_usec)
    field(:last_start_at, :utc_datetime_usec)
    field(:reset_reason, :string)
    field(:last_seen_at, :utc_datetime_usec)

    has_many(:devices, Broom.Device, references: :id, foreign_key: :host_id)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(p) when is_struct(p) do
    Map.from_struct(p) |> changeset()
  end

  def changeset(p) when is_map(p) do
    # allow changeset to consume MsgIn without creating a direct dependency while also allowing
    # host instead of ident
    %{
      ident: p[:host] || p[:ident],
      name: p[:name] || p[:ident],
      last_start_at: p[:last_start_at] || p[:sent_at],
      last_seen_at: p[:last_seen_at] || p[:sent_at]
    }
    |> Map.merge(p[:data] || %{})
    |> changeset(%Schema{})
  end

  def changeset(p, %Schema{} = host) when is_map(p), do: changeset(host, p)

  def changeset(%Schema{} = host, p) when is_map(p) do
    alias Ecto.Changeset

    host
    |> Changeset.cast(p, columns(:cast))
    |> Changeset.validate_required(columns(:required))
    |> Changeset.validate_format(:ident, ~r/^[a-z]+[.][[:alnum:]]{3,}$/i)
    |> Changeset.validate_length(:ident, max: 32)
    |> Changeset.validate_format(:name, ~r/^[a-z~][\w .:-]+[[:alnum:]]$/i)
    |> Changeset.validate_length(:name, max: 128)
    |> Changeset.validate_length(:name, max: 128)
    |> Changeset.validate_format(:profile, ~r/^[a-z]+[\w.-]+$/i)
    |> Changeset.validate_length(:profile, max: 128)
    |> validate_profile_exists()
    |> Changeset.validate_length(:firmware_vsn, max: 64)
    |> Changeset.validate_length(:idf_vsn, max: 64)
    |> Changeset.validate_length(:app_sha, max: 64)
    |> Changeset.validate_length(:reset_reason, max: 64)
  end

  def columns(:all) do
    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
  end

  def columns(:cast), do: columns(:all)
  def columns(:required), do: columns_all(only: [:ident, :name, :last_seen_at, :last_start_at])
  def columns(:replace), do: columns_all(drop: [:ident, :authorized, :inserted_at])

  def columns_all(opts) when is_list(opts) do
    case opts do
      [drop: x] ->
        keep_set = columns(:all) |> MapSet.new()
        drop_set = x |> MapSet.new()

        MapSet.difference(keep_set, drop_set) |> MapSet.to_list()

      [only: keep] ->
        keep
    end
  end

  def get_devices(%Schema{id: id}) do
    Repo.all(Broom.Device, host_id: id)
  end

  def idents_begin_with(pattern) when is_binary(pattern) do
    like_string = IO.iodata_to_binary([pattern, "%"])

    Query.from(x in Schema,
      where: like(x.ident, ^like_string),
      order_by: x.ident,
      select: x.ident
    )
    |> Repo.all()
  end

  def insert_opts do
    [on_conflict: {:replace, columns(:replace)}, returning: true, conflict_target: [:ident]]
  end

  def update_last_seen_at(id, %DateTime{} = at) when is_integer(id) do
    alias Ecto.Changeset

    Repo.get!(Schema, id)
    |> Changeset.cast(%{last_seen_at: at}, [:last_seen_at])
    |> Changeset.validate_required([:last_seen_at])
    |> Repo.update!(returning: true)
  end

  # NOTE: stubbed for the reference implementation
  defp validate_profile_exists(%Ecto.Changeset{} = cs), do: cs
end
