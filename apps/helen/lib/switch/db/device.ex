defmodule Switch.DB.Device do
  @moduledoc """
  Database functionality for Switch Device
  """

  use Ecto.Schema

  alias Switch.DB.Alias, as: Alias
  alias Switch.DB.Device, as: Schema

  schema "switch_device" do
    field(:device, :string)
    field(:host, :string)
    field(:pio_count, :integer)
    field(:dev_latency_us, :integer, default: 0)
    field(:last_seen_at, :utc_datetime_usec)

    has_many(:aliases, Alias, references: :id, foreign_key: :device_id)

    timestamps(type: :utc_datetime_usec)
  end

  # (1 of 2) convert parms into a map
  def changeset(%Schema{} = d, p) when is_list(p), do: changeset(d, Enum.into(p, %{}))

  # (2 of 2) params are a map
  def changeset(%Schema{} = d, p) when is_map(p) do
    import Common.DB, only: [name_regex: 0]
    alias Ecto.Changeset

    d
    |> Changeset.cast(p, columns(:cast))
    |> Changeset.validate_required(columns(:required))
    |> Changeset.validate_format(:device, name_regex())
    |> Changeset.validate_format(:host, name_regex())
    |> Changeset.validate_number(:dev_latency_us, greater_than_or_equal_to: 0)
  end

  def columns(:all) do
    import List, only: [flatten: 1]
    import Map, only: [drop: 2, from_struct: 1, keys: 1]

    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> flatten()

    %Schema{} |> from_struct() |> drop(these_cols) |> keys() |> flatten()
  end

  def columns(:cast), do: columns(:all)
  def columns(:required), do: columns_all(drop: [:inserted_at, :updated_at])
  def columns(:replace), do: columns_all(drop: [:device, :inserted_at])

  def columns_all(opts) when is_list(opts) do
    keep_set = MapSet.new(opts[:only] || columns(:all))
    drop_set = MapSet.new(opts[:drop] || columns(:all))

    MapSet.difference(keep_set, drop_set) |> MapSet.to_list()
  end

  def devices_begin_with(pattern) when is_binary(pattern) do
    import Ecto.Query, only: [from: 2]
    import IO, only: [iodata_to_binary: 1]

    like_string = iodata_to_binary([pattern, "%"])

    from(x in Schema,
      where: like(x.device, ^like_string),
      order_by: x.device,
      select: x.device
    )
    |> Repo.all()
  end

  # (1 of 2) find with proper opts
  def find(opts) when is_list(opts) and opts != [] do
    import Repo, only: [get_by: 2]

    case get_by(Schema, opts) do
      %Schema{} = x -> preload(x)
      x when is_nil(x) -> nil
    end
  end

  # (2 of 2) validate param and build opts for find/2
  def find(id_or_device) do
    case id_or_device do
      x when is_binary(x) -> find(device: x)
      x when is_integer(x) -> find(id: x)
      x -> {:bad_args, "must be binary or integer: #{inspect(x)}"}
    end
  end

  def find_alias(%Schema{aliases: aliases}, pio) when is_integer(pio) and pio >= 0 do
    Enum.find(aliases, nil, fn dev_alias -> Alias.for_pio?(dev_alias, pio) end)
  end

  def make_remote_states(%Schema{} = d) do
    import Alias, only: [assemble_state: 1]
    %Schema{aliases: aliases} = reload(d)

    for %Alias{} = a <- aliases, do: assemble_state(a)
  end

  # (1 of 2) load aliases if needed
  def load_aliases({rc, %Schema{} = d}) when rc == :ok do
    if Ecto.assoc_loaded?(d.aliases) do
      {rc, d}
    else
      {rc, Repo.preload(d, [:aliases])}
    end
  end

  # (2 of 2) previous query failed, pass through
  def load_aliases(x), do: x

  def pio_aliased?(%Schema{id: id, pio_count: pio_count}, pio) when pio < pio_count do
    import Ecto.Query, only: [from: 2]
    import Repo, only: [get_by: 2]

    d = get_by(Schema, id: id)

    case Repo.preload(d, aliases: from(a in Alias, where: a.pio == ^pio)) do
      %Schema{aliases: []} -> false
      %Schema{aliases: x} when is_list(x) -> true
    end
  end

  def pio_count(%Schema{pio_count: pio_count}), do: pio_count

  def preload(%Schema{} = x), do: Repo.preload(x, [:aliases])

  def reload(%Schema{id: id}) do
    import Repo, only: [get!: 2]

    get!(Schema, id) |> preload()
  end

  # (1 of 2) receive the inbound msg, grab the keys of interest
  def upsert(%{device: _, host: _} = msg) do
    import Helen.Time.Helper, only: [utc_now: 0]

    want = [:device, :host, :pio_count, :dev_latency_us, :last_seen_at]

    p = Map.take(msg, want) |> put_in([:last_seen_at], utc_now())

    put_in(msg, [:device], upsert(%Schema{}, p))
  end

  # (2 of 2) perform the actual insert with conflict check (upsert)
  def upsert(%Schema{} = d, p) when is_map(p) do
    # assemble the opts for upsert
    # check for conflicts on :device
    # if there is a conflict only replace specified columns
    opts = [on_conflict: {:replace, columns(:replace)}, returning: true, conflict_target: [:device]]

    changeset(d, p) |> Repo.insert(opts) |> load_aliases()
  end
end
