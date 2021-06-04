defmodule Sally.Remote.DB.Host do
  require Logger

  use Ecto.Schema
  require Ecto.Query
  alias Ecto.Query

  alias Sally.Remote.DB.Alias
  alias Sally.Remote.DB.Host, as: Schema
  alias Sally.Repo

  schema "remote_host" do
    field(:ident, :string)
    field(:firmware_vsn, :string)
    field(:idf_vsn, :string)
    field(:app_sha, :string)
    field(:build_at, :utc_datetime_usec)
    field(:last_start_at, :utc_datetime_usec)
    field(:reset_reason, :string)
    field(:last_seen_at, :utc_datetime_usec)

    has_many(:aliases, Alias, references: :id, foreign_key: :host_id)

    timestamps(type: :utc_datetime_usec)
  end

  @ident_max_length 128

  def changeset(%Schema{} = d, p) when is_map(p) do
    alias Ecto.Changeset

    d
    |> Changeset.cast(p, columns(:cast))
    |> Changeset.validate_required(columns(:required))
    |> Changeset.validate_format(:ident, name_regex())
    |> Changeset.validate_length(:ident, max: @ident_max_length)
    |> Changeset.validate_format(:ident, name_regex())
  end

  def get_aliases(%Schema{id: id}) do
    Repo.all(Alias, device_id: id)
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

  def update_last_seen_at(id, %DateTime{} = at) when is_integer(id) do
    alias Ecto.Changeset

    Repo.get!(Schema, id)
    |> Changeset.cast(%{last_seen_at: at}, [:last_seen_at])
    |> Changeset.validate_required([:last_seen_at])
    |> Repo.update!(returning: true)
  end

  def upsert(p) when is_map(p) do
    # assemble the opts for upsert
    # check for conflicts on :ident
    # if there is a conflict only replace specified columns
    opts = [on_conflict: {:replace, columns(:replace)}, returning: true, conflict_target: [:ident]]

    changeset(%Schema{}, p) |> Repo.insert!(opts)
  end

  defp columns(:all) do
    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
  end

  defp columns(:cast), do: columns(:all)
  defp columns(:required), do: columns_all(only: [:ident, :last_seen_at])
  defp columns(:replace), do: columns_all(drop: [:ident, :inserted_at])

  defp columns_all(opts) when is_list(opts) do
    keep_set = MapSet.new(opts[:only] || columns(:all))
    drop_set = MapSet.new(opts[:drop] || columns(:all))

    MapSet.difference(keep_set, drop_set) |> MapSet.to_list()
  end

  # validate name:
  #  -starts with a ~ or alpha char
  #  -contains a mix of:
  #      alpha numeric, slash (/), dash (-), underscore (_), colon (:) and
  #      spaces
  #  -ends with an alpha char
  defp name_regex, do: ~r'^[\\~\w]+[\w\\ \\/\\:\\.\\_\\-]{1,}[\w]$'
end
