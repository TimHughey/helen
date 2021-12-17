defmodule Sally.Host do
  require Logger

  use Ecto.Schema
  alias Ecto.Changeset

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

  def changeset_with_name_constraint(%Schema{} = schema, changes, required) do
    changeset(schema, changes, required) |> Changeset.unique_constraint(:name)
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

  def find_by(opts) when is_list(opts), do: Repo.get_by(Schema, opts)

  def find_by_ident(ident), do: Repo.get_by(Schema, ident: ident)
  def find_by_name(name), do: Repo.get_by(Schema, name: name)

  def idents_begin_with(pattern) when is_binary(pattern) do
    import Ecto.Query, only: [from: 2]

    like_string = IO.iodata_to_binary([pattern, "%"])

    from(x in Schema,
      where: like(x.ident, ^like_string),
      order_by: x.ident,
      select: x.ident
    )
    |> Repo.all()
  end

  def insert_opts(replace_columns \\ columns(:replace)) do
    [on_conflict: {:replace, replace_columns}, returning: true, conflict_target: [:ident]]
  end

  def latest(opts) do
    import Ecto.Query, only: [from: 2]

    {want_schema, opts_rest} = Keyword.pop(opts, :schema, false)
    {age_opts, _opts_rest} = Keyword.pop(opts_rest, :age, hours: -1)

    before = Timex.now() |> Timex.shift(age_opts)

    from(x in Schema,
      where: x.inserted_at >= ^before,
      order_by: [desc: x.inserted_at],
      limit: 1
    )
    |> Repo.one()
    |> then(fn result ->
      case result do
        %Schema{} = x when want_schema == true -> x
        %Schema{ident: ident} -> ident
        _ -> :none
      end
    end)

    # host = Repo.one(q)

    # cond do
    #   is_nil(host) -> nil
    #   opts[:schema] == true -> host
    #   true -> host.ident
    # end
  end

  def live(opts \\ []) when is_list(opts) do
    import Ecto.Query, only: [from: 2]

    {utc_now, opts_rest} = Keyword.pop(opts, :utc_now, DateTime.utc_now())
    {recent_opts, _opts_rest} = Keyword.pop(opts_rest, :recent, minutes: -1)

    since_dt = utc_now |> Timex.shift(recent_opts)

    from(x in Schema, where: x.last_seen_at >= ^since_dt, order_by: [asc: x.name])
    |> Repo.all()
  end

  defp profiles_path do
    [System.get_env(@helen_base), @profiles_dir] |> Path.join()
  end

  def unnamed do
    import Ecto.Query, only: [from: 2]

    from(x in Schema, where: x.ident == x.name, order_by: [desc: x.last_start_at]) |> Repo.all()
  end

  def rename(opts) when is_list(opts) do
    with {:opts, from} when is_binary(from) <- {:opts, opts[:from]},
         {:opts, to} when is_binary(to) <- {:opts, opts[:to]},
         {:found, %Schema{} = x} <- {:found, find_by_name(from)},
         cs <- changeset_with_name_constraint(x, %{name: to}, [:name]),
         {:ok, %Schema{} = updated_schema} <- Repo.update(cs, returning: true) do
      updated_schema
    else
      {:opts, _} -> {:bad_args, opts}
      {:found, nil} -> {:not_found, opts[:from]}
      {:error, %Changeset{} = cs} -> {:name_taken, cs.changes.name}
    end
  end

  def retire(%Schema{} = schema) do
    changes = %{authorized: false, name: schema.ident, reset_reason: "retired"}

    changeset(schema, changes, Map.keys(changes)) |> Repo.update(returning: true)
  end

  def setup(%Schema{} = schema, opts) do
    changes = Enum.into(opts, %{authorized: true})

    changeset(schema, changes, Map.keys(changes)) |> Repo.update(returning: true)
  end

  def summary(%Schema{} = x), do: Map.take(x, [:name, :ident, :profile, :last_seen_at])

  defp validate_profile_exists(%Changeset{} = cs) do
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
