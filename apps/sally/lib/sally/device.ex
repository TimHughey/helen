defmodule Sally.Device do
  @moduledoc """
  Database implementation of Sally.PulseWidth devices
  """

  require Logger

  use Ecto.Schema
  require Ecto.Query

  alias __MODULE__, as: Schema
  alias Sally.{DevAlias, Host, Repo}

  schema "device" do
    field(:ident, :string)
    field(:family, :string)
    field(:mutable, :boolean)
    field(:pios, :integer)
    field(:last_seen_at, :utc_datetime_usec)

    belongs_to(:host, Host)
    has_many(:aliases, DevAlias, foreign_key: :device_id, preload_order: [asc: :pio])

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, %Host{} = host) when is_struct(struct) do
    p = Map.from_struct(struct)
    merge_data = Map.drop(p.data, [:mut, :mutable, :pios])

    device = Ecto.build_assoc(host, :devices)

    %{
      ident: p[:ident],
      family: p[:category] || p[:family],
      mutable: p.data[:mut] || p.data[:mutable],
      pios: p.data[:pios],
      last_seen_at: p[:sent_at]
    }
    |> Map.merge(merge_data)
    |> changeset(device)
  end

  def changeset(p, %Schema{} = device) when is_map(p), do: changeset(device, p)

  def changeset(%Schema{} = device, p) when is_map(p) do
    alias Ecto.Changeset

    device
    |> Changeset.cast(p, columns(:cast))
    |> Changeset.validate_required(columns(:required))
    |> Changeset.validate_format(:ident, ~r/^[a-z~][\w .:-]+[[:alnum:]]$/i)
    |> Changeset.validate_length(:ident, max: 128)
    |> Changeset.validate_format(:family, ~r/^[pwm]|[ds]|[i2c]$/)
    |> Changeset.validate_number(:pios, greater_than_or_equal_to: 1)
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

  # # (1 of 2) find with proper opts
  # def find(opts) when is_list(opts) and opts != [] do
  #   case Repo.get_by(Schema, opts) do
  #     %Schema{} = x -> preload(x)
  #     x when is_nil(x) -> nil
  #   end
  # end
  #
  # # (2 of 2) validate param and build opts for find/2
  # def find(id_or_ident) do
  #   case id_or_ident do
  #     x when is_binary(x) -> find(ident: x)
  #     x when is_integer(x) -> find(id: x)
  #     x -> {:bad_args, "must be binary or integer: #{inspect(x)}"}
  #   end
  # end

  # def find_alias(%Schema{aliases: aliases}, pio) when is_integer(pio) and pio >= 0 do
  #   Enum.find(aliases, nil, fn dev_alias -> DevAlias.for_pio?(dev_alias, pio) end)
  # end
  #
  # def get_aliases(%Schema{id: id}) do
  #   Repo.all(DevAlias, device_id: id)
  # end

  def idents_begin_with(pattern) when is_binary(pattern) do
    like_string = "#{pattern}%"

    Ecto.Query.from(x in Schema,
      where: like(x.ident, ^like_string),
      order_by: x.ident,
      select: x.ident
    )
    |> Repo.all()
  end

  def insert_opts do
    [on_conflict: {:replace, columns(:replace)}, returning: true, conflict_target: [:ident]]
  end

  def pio_aliased?(%Schema{pios: pios} = device, pio) when pio < pios do
    aliased? = fn
      %Schema{aliases: []} -> false
      %Schema{aliases: x} when is_list(x) -> true
    end

    device
    |> Repo.reload()
    |> Repo.preload(aliases: Ecto.Query.from(a in DevAlias, where: a.pio == ^pio))
    |> aliased?.()
  end

  def pios(%Schema{pios: pios}), do: pios

  def preload(%Schema{} = x), do: Repo.preload(x, [:aliases])
end
