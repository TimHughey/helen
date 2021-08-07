defmodule Sally.Host do
  require Logger

  use Ecto.Schema
  require Ecto.Query

  alias Ecto.Query

  alias Sally.Host, as: Schema
  alias Sally.Host.ChangeControl
  alias Sally.Repo

  schema "host" do
    field(:ident, :string)
    field(:name, :string)
    field(:profile, :string, default: "generic")
    field(:authorized, :boolean, default: false)
    field(:firmware_vsn, :string)
    field(:idf_vsn, :string)
    field(:app_sha, :string)
    field(:build_at, :utc_datetime_usec)
    field(:last_start_at, :utc_datetime_usec)
    field(:reset_reason, :string)
    field(:last_seen_at, :utc_datetime_usec)

    has_many(:devices, Sally.Device, references: :id, foreign_key: :host_id)

    timestamps(type: :utc_datetime_usec)
  end

  @helen_base "HELEN_BASE"
  @profiles_dir Application.compile_env!(:sally, [Sally.Host, :profiles_path])
  # @env_profile_path Application.compile_env!(:sally, [Sally.Host, :env_vars, :profile_path])

  def authorize(name, val \\ true) when is_boolean(val) do
    case Repo.get_by(Schema, name: name) do
      %Schema{} = h -> changeset(h, %{authorized: val}, [:authorized]) |> Repo.update!()
      nil -> nil
    end
  end

  def boot_payload_data(%Schema{} = h) do
    # file = [System.get_env(@env_profile_path, "/tmp"), "profiles", "#{h.profile}.toml"] |> Path.join()

    file = [profiles_path(), "#{h.profile}.toml"] |> Path.join()

    Toml.decode_file!(file)
  end

  # (1 of 2) accept a ChangeControl
  def changeset(%ChangeControl{} = cc) do
    changeset(%Schema{}, cc.raw_changes, cc.required)
  end

  # (2 of 2) traditional implementation accepting a Schema, changes and what's required
  def changeset(%Schema{} = schema, changes, required) do
    alias Ecto.Changeset

    schema
    |> Changeset.cast(changes, required)
    |> Changeset.validate_required(required)
    |> Changeset.validate_format(:ident, ~r/^[a-z]+[.][[:alnum:]]{3,}$/i)
    |> Changeset.validate_length(:ident, max: 24)
    |> Changeset.validate_format(:name, ~r/^[a-z~][\w .:-]+[[:alnum:]]$/i)
    |> Changeset.validate_length(:name, max: 32)
    |> Changeset.validate_format(:profile, ~r/^[a-z]+[\w.-]+$/i)
    |> Changeset.validate_length(:profile, max: 32)
    |> validate_profile_exists()
    |> Changeset.validate_length(:firmware_vsn, max: 32)
    |> Changeset.validate_length(:idf_vsn, max: 12)
    |> Changeset.validate_length(:app_sha, max: 12)
    |> Changeset.validate_length(:reset_reason, max: 24)
  end

  def columns(:all) do
    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
  end

  def columns(:cast), do: columns(:all)
  def columns(:required), do: columns_all(only: [:ident, :name, :last_seen_at, :last_start_at])
  def columns(:replace), do: columns_all(drop: [:ident, :name, :profile, :authorized, :inserted_at])

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

  def deauthorize(name), do: authorize(name, false)

  def find_by_ident(ident), do: Repo.get_by(Schema, ident: ident)
  def find_by_name(name), do: Repo.get_by(Schema, name: name)

  def get_devices(%Schema{id: id}) do
    Repo.all(Sally.Device, host_id: id)
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

  def insert_opts(replace_columns \\ columns(:replace)) do
    [on_conflict: {:replace, replace_columns}, returning: true, conflict_target: [:ident]]
  end

  defp profiles_path do
    [System.get_env(@helen_base), @profiles_dir] |> Path.join()
  end

  defp validate_profile_exists(%Ecto.Changeset{} = cs) do
    alias Ecto.Changeset

    #  profile_dir = [System.get_env("RUTH_CONFIG_PATH", "/tmp"), "profiles"] |> Path.join()

    case Changeset.fetch_field(cs, :profile) do
      {_src, profile} ->
        file = "#{profile}.toml"
        file_path = [profiles_path(), file] |> Path.join()

        case Toml.decode_file(file_path, filename: file_path) do
          {:ok, _profile} -> cs
          {:error, reason} -> Changeset.add_error(cs, :profile, reason)
        end

      :error ->
        Logger.info(inspect(cs, pretty: true))
        cs
    end
  end
end
