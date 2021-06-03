defmodule Sally.PulseWidth.DB.Device do
  @moduledoc """
  Database implementation of Sally.PulseWidth devices
  """

  require Logger

  use Ecto.Schema
  require Ecto.Query
  alias Ecto.Query

  alias Sally.PulseWidth.DB.Alias, as: Alias
  alias Sally.PulseWidth.DB.Device, as: Schema
  alias SallyRepo, as: Repo

  schema "pwm_device" do
    field(:ident, :string)
    field(:host, :string)
    field(:pios, :integer)
    field(:latency_us, :integer, default: 0)
    field(:last_seen_at, :utc_datetime_usec)

    has_many(:aliases, Alias, references: :id, foreign_key: :device_id, preload_order: [asc: :pio])

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(%Schema{} = d, p) when is_map(p) do
    alias Ecto.Changeset

    d
    |> Changeset.cast(p, columns(:cast))
    |> Changeset.validate_required(columns(:required))
    |> Changeset.validate_format(:ident, name_regex())
    |> Changeset.validate_format(:host, name_regex())
    |> Changeset.validate_number(:latency_us, greater_than_or_equal_to: 0)
  end

  def columns(:all) do
    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
  end

  def columns(:cast), do: columns(:all)
  def columns(:required), do: columns_all(drop: [:inserted_at, :updated_at])
  def columns(:replace), do: columns_all(drop: [:ident, :inserted_at])

  def columns_all(opts) when is_list(opts) do
    keep_set = MapSet.new(opts[:only] || columns(:all))
    drop_set = MapSet.new(opts[:drop] || columns(:all))

    MapSet.difference(keep_set, drop_set) |> MapSet.to_list()
  end

  # (1 of 2) find with proper opts
  def find(opts) when is_list(opts) and opts != [] do
    case Repo.get_by(Schema, opts) do
      %Schema{} = x -> preload(x)
      x when is_nil(x) -> nil
    end
  end

  # (2 of 2) validate param and build opts for find/2
  def find(id_or_ident) do
    case id_or_ident do
      x when is_binary(x) -> find(ident: x)
      x when is_integer(x) -> find(id: x)
      x -> {:bad_args, "must be binary or integer: #{inspect(x)}"}
    end
  end

  def find_alias(%Schema{aliases: aliases}, pio) when is_integer(pio) and pio >= 0 do
    Enum.find(aliases, nil, fn dev_alias -> Alias.for_pio?(dev_alias, pio) end)
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

  def pio_aliased?(%Schema{id: id, pios: pios}, pio) when pio < pios do
    d = Repo.get_by(Schema, id: id)

    case Repo.preload(d, aliases: Query.from(a in Alias, where: a.pio == ^pio)) do
      %Schema{aliases: []} -> false
      %Schema{aliases: x} when is_list(x) -> true
    end
  end

  def load_aliases(schema_or_id), do: Repo.preload(schema_or_id, [:aliases])

  def pios(%Schema{pios: pios}), do: pios

  def preload(%Schema{} = x), do: Repo.preload(x, [:aliases])

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

  # validate name:
  #  -starts with a ~ or alpha char
  #  -contains a mix of:
  #      alpha numeric, slash (/), dash (-), underscore (_), colon (:) and
  #      spaces
  #  -ends with an alpha char
  defp name_regex, do: ~r'^[\\~\w]+[\w\\ \\/\\:\\.\\_\\-]{1,}[\w]$'
end
