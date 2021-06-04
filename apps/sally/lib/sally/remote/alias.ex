defmodule Sally.Remote.DB.Alias do
  @moduledoc """
  Database implementation of Sally.Remote Aliases
  """
  require Logger

  use Ecto.Schema
  require Ecto.Query
  alias Ecto.Query

  alias Sally.Remote.DB.Alias, as: Schema
  alias Sally.Remote.DB.{Command, Datapoint, Host}
  alias Sally.Repo

  @profile_default "generic"
  @ttl_default 2000
  @ttl_min 50

  schema "remote_alias" do
    field(:name, :string)
    field(:description, :string, default: "<none>")
    field(:cmd, :string, default: "<created>")
    field(:profile, :string, default: @profile_default)
    field(:ttl_ms, :integer, default: @ttl_default)

    belongs_to(:host, Host)
    has_many(:cmds, Command, foreign_key: :alias_id, preload_order: [desc: :sent_at])

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(changes, %Schema{} = a) do
    alias Ecto.Changeset

    a
    |> Changeset.cast(changes, columns(:cast))
    |> Changeset.validate_required(columns(:required))
    |> Changeset.validate_length(:name, min: 3, max: 32)
    |> Changeset.validate_format(:name, name_regex())
    |> Changeset.validate_length(:profile, min: 1, max: 32)
    |> Changeset.validate_format(:profile, profile_regex())
    |> validate_profile_exists()
    |> Changeset.validate_length(:cmd, min: 2, max: 32)
    |> Changeset.validate_length(:description, max: 50)
    |> Changeset.validate_number(:ttl_ms, greater_than_or_equal_to: @ttl_min)
    |> Changeset.unique_constraint(:name, [:name])
  end

  # helpers for changeset columns
  def columns(:all) do
    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
  end

  def columns(:cast), do: columns(:all)
  def columns(:required), do: columns_all(only: [:host_id, :name, :profile])
  def columns(:replace), do: columns_all(drop: [:name, :inserted_at])

  def columns_all(opts) when is_list(opts) do
    keep_set = MapSet.new(opts[:only] || columns(:all))
    drop_set = MapSet.new(opts[:drop] || columns(:all))

    MapSet.difference(keep_set, drop_set) |> MapSet.to_list()
  end

  def create(%Host{} = host, opts) do
    dev_alias = Ecto.build_assoc(host, :aliases)

    %{
      name: opts[:name],
      profile: opts[:profile] || @profile_default,
      description: opts[:description] || "<none>",
      ttl_ms: opts[:ttl_ms] || @ttl_default
    }
    |> upsert(dev_alias)
  end

  def delete(name_or_id) do
    with %Schema{} = a <- find(name_or_id) |> load_command_ids(),
         {:ok, count} <- Command.purge(a, :all),
         {:ok, %Schema{name: n}} <- Repo.delete(a) do
      {:ok, [name: n, commands: count]}
    else
      nil -> {:unknown, name_or_id}
      error -> error
    end
  end

  def exists?(name_or_id) do
    case find(name_or_id) do
      %Schema{} -> true
      _anything -> false
    end
  end

  # (1 of 2) find with proper opts
  def find(opts) when is_list(opts) and opts != [] do
    case Repo.get_by(Schema, opts) do
      %Schema{} = x -> load_host(x) |> load_cmd_last()
      x when is_nil(x) -> nil
    end
  end

  # (2 of 2) validate param and build opts for find/2
  def find(id_or_schema) do
    case id_or_schema do
      x when is_binary(x) -> find(name: x)
      x when is_integer(x) -> find(id: x)
      x -> {:bad_args, "must be binary or integer: #{inspect(x)}"}
    end
  end

  def names do
    Query.from(x in Schema, select: x.name, order_by: x.name) |> Repo.all()
  end

  def names_begin_with(pattern) when is_binary(pattern) do
    like_string = [pattern, "%"] |> IO.iodata_to_binary()
    q = Query.from(x in Schema, where: like(x.name, ^like_string), order_by: x.name, select: x.name)

    Repo.all(q)
  end

  def update_cmd(alias_id, cmd) when is_integer(alias_id) do
    Repo.get!(Schema, alias_id) |> update_cmd(cmd)
  end

  def update_cmd(%Schema{} = dev_alias, cmd) do
    alias Ecto.Changeset

    dev_alias
    |> Changeset.cast(%{cmd: cmd}, [:cmd])
    |> Changeset.validate_required([:cmd])
    |> Changeset.validate_length(:cmd, max: 32)
    |> Repo.update!(returning: true, force: true)
  end

  defp load_command_ids(schema_or_nil) do
    q = Query.from(c in Command, select: [:id])
    Repo.preload(schema_or_nil, [cmds: q], force: true)
  end

  def load_host(schema_or_tuple) do
    case schema_or_tuple do
      {:ok, %Schema{} = a} -> {:ok, Repo.preload(a, [:host])}
      %Schema{} = a -> Repo.preload(a, [:host])
      x -> x
    end
  end

  def load_cmd_last(%Schema{} = x) do
    Repo.preload(x, cmds: Query.from(d in Command, order_by: [desc: d.sent_at], limit: 1))
  end

  # validate name:
  #  -starts with a ~ or alpha char
  #  -contains a mix of:
  #      alpha numeric, slash (/), dash (-), underscore (_), colon (:) and
  #      spaces
  #  -ends with an alpha char
  defp name_regex, do: ~r'^[a-zA-Z]+[\w.:-]+$'

  defp profile_regex, do: ~r'^[a-zA-Z]+[\w-]+$'

  defp upsert(params, %Schema{} = schema) when is_map(params) do
    insert_opts = [on_conflict: {:replace, columns(:replace)}, returning: true, conflict_target: [:name]]

    params
    |> changeset(schema)
    |> Repo.insert(insert_opts)
  end

  defp validate_profile_exists(%Ecto.Changeset{} = cs) do
    alias Ecto.Changeset

    profile_dir = [System.get_env("RUTH_TOML", "/tmp"), "profiles"] |> Path.join()

    case Changeset.get_change(cs, :profile) do
      x when is_binary(x) ->
        profile_file = [profile_dir, x] |> Path.join()

        case Toml.decode_file(profile_file, filename: profile_file) do
          {:ok, _} -> cs
          {:error, reason} -> Changeset.add_error(cs, :profile, reason)
        end

      _ ->
        cs
    end
  end
end
