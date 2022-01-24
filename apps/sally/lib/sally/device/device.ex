defmodule Sally.Device do
  @moduledoc """
  Database implementation of Sally.PulseWidth devices
  """

  require Logger
  use Ecto.Schema

  alias Ecto.Changeset

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

    ident = List.first(p.filter_extra)
    mutable? = p.subsystem == "mut"
    device = Ecto.build_assoc(host, :devices)
    pios = if(mutable?, do: length(p.data[:pins]), else: 1)

    %{
      ident: ident,
      family: determine_family(ident),
      mutable: mutable?,
      pios: pios,
      last_seen_at: p[:sent_at]
    }
    |> changeset(device)
  end

  def changeset(changes, %Host{} = host) when is_map(changes) do
    Ecto.build_assoc(host, :devices) |> changeset(changes)
  end

  def changeset(p, %Schema{} = device) when is_map(p) do
    changeset(device, p)
  end

  def changeset(%Schema{} = device, p) when is_map(p) do
    device
    |> Changeset.cast(p, columns(:cast))
    |> Changeset.validate_required(columns(:required))
    |> Changeset.validate_format(:ident, ~r/^[a-z~]{1,}[[:alnum:]][\w .:-]+[[:alnum:]]$/i)
    |> Changeset.validate_length(:ident, max: 128)
    |> Changeset.validate_format(:family, ~r/^[pwm]|[ds]|[i2c]$/)
    |> Changeset.validate_number(:pios, greater_than_or_equal_to: 1)
  end

  @columns_all [:ident, :family, :mutable, :pios, :last_seen_at, :updated_at, :inserted_at]
  def columns(:cast), do: @columns_all
  def columns(:required), do: columns_exclude([:inserted_at, :updated_at])
  def columns(:replace), do: columns_exclude([:last_seen_at, :updated_at])

  def columns_exclude(cols), do: Enum.reject(@columns_all, fn key -> key in cols end)

  # (1 of 2) find with proper opts
  def find(opts) when is_list(opts) and opts != [] do
    case Repo.get_by(Schema, opts) do
      %Schema{} = x -> preload(x)
      x when is_nil(x) -> nil
    end
  end

  # # (2 of 2) validate param and build opts for find/2
  def find(id_or_ident) do
    case id_or_ident do
      x when is_binary(x) -> find(ident: x)
      x when is_integer(x) -> find(id: x)
      x -> {:bad_args, "must be binary or integer: #{inspect(x)}"}
    end
  end

  # def find_alias(%Schema{aliases: aliases}, pio) when is_integer(pio) and pio >= 0 do
  #   Enum.find(aliases, nil, fn dev_alias -> DevAlias.for_pio?(dev_alias, pio) end)
  # end
  #
  # def get_aliases(%Schema{id: id}) do
  #   Repo.all(DevAlias, device_id: id)
  # end

  def idents_begin_with(pattern) when is_binary(pattern) do
    import Ecto.Query, only: [from: 2]

    like_string = "#{pattern}%"

    from(x in Schema,
      where: like(x.ident, ^like_string),
      order_by: x.ident,
      select: x.ident
    )
    |> Repo.all()
  end

  def insert_opts do
    [on_conflict: {:replace, columns(:replace)}, returning: true, conflict_target: [:ident]]
  end

  # def last_seen_at_cs(id, last_seen_at \\ nil) do
  #   alias Ecto.Changeset
  #
  #   at = if(is_nil(id), do: DateTime.utc_now(), else: last_seen_at)
  #
  #   changes = %{id: id, last_seen_at: at}
  #
  #   %Schema{}
  #   |> Changeset.cast(changes, Map.keys(changes))
  # end

  def latest(opts) do
    import Ecto.Query, only: [from: 2]

    age = opts[:age] || [hours: -1]
    schema = if opts[:schema] == true, do: true, else: false
    before = Timex.now() |> Timex.shift(age)

    from(x in Schema,
      where: x.inserted_at >= ^before,
      order_by: [desc: x.inserted_at],
      limit: 1
    )
    |> Repo.one()
    |> then(fn result ->
      case result do
        %Schema{} = x when schema == true -> x
        %Schema{ident: ident} -> ident
        _ -> :none
      end
    end)
  end

  def load_aliases(device) do
    Repo.preload(device, [:aliases])
  end

  def load_host(device) do
    Repo.preload(device, [:host])
  end

  def move_aliases(src_ident, dest_ident) do
    with {:src, %Schema{} = src_dev} <- {:src, find(src_ident)},
         {:dest, %Schema{aliases: []} = dest_dev} <- {:dest, find(dest_ident)} do
      dest_dev
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:aliases, src_dev.aliases)
      |> Repo.update()
    else
      {:dest, %Schema{ident: ident}} -> {:error, "destination #{ident} must not have any aliases"}
      {:src, _} -> {:not_found, src_ident}
      {:dest, _} -> {:not_found, dest_ident}
    end
  end

  def name_registration_opts(%Schema{} = device, opts) do
    case device do
      %{mutable: true} -> :cmds
      %{mutable: false} -> :datapoints
    end
    |> then(fn nature -> [{:nature, nature} | opts] end)
  end

  def pio_check(schema, opts) when is_list(opts) do
    case schema do
      %Schema{mutable: true} -> opts[:pio]
      %Schema{mutable: false} -> 0
      _ -> nil
    end
  end

  def pio_aliased?(%Schema{pios: pios} = device, pio) when pio < pios do
    import Ecto.Query, only: [from: 2]

    device
    |> Repo.reload()
    |> Repo.preload(aliases: from(a in DevAlias, where: a.pio == ^pio))
    |> then(fn
      %Schema{aliases: []} -> false
      %Schema{aliases: x} when is_list(x) -> true
    end)
  end

  def pios(%Schema{pios: pios}), do: pios

  def preload(%Schema{} = x), do: Repo.preload(x, [:aliases])

  def seen_at_cs(%{aliases: dev_aliases, seen_at: seen_at} = _multi_changes) do
    case dev_aliases do
      [%Sally.DevAlias{device_id: id} | _] -> id
      %Sally.DevAlias{device_id: id} -> id
      _ -> raise("could not find device id in: #{inspect(dev_aliases)}")
    end
    |> seen_at_cs(seen_at)
  end

  def seen_at_cs(id, %DateTime{} = at) when is_integer(id) do
    struct(__MODULE__, id: id) |> Changeset.cast(%{last_seen_at: at}, [:last_seen_at])
  end

  def summary(%Schema{} = x), do: Map.take(x, [:ident, :last_seen_at])

  def type(schema_or_id) do
    case schema_or_id do
      %Schema{} = x -> if(x.mutable, do: :mutable, else: :immutable)
      x when is_integer(x) -> Repo.get(Schema, x) |> type()
      x when is_nil(x) -> :unknown
    end
  end

  defp determine_family(ident) do
    case ident do
      <<"ds"::utf8, _rest::binary>> -> "ds"
      <<"pwm"::utf8, _rest::binary>> -> "pwm"
      <<"i2c"::utf8, _rest::binary>> -> "i2c"
      _ -> "unsupported"
    end
  end
end
