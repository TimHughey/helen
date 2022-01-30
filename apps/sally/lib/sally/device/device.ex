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

  @returned [returning: true]

  def changeset(changes, %Host{} = host) when is_map(changes) do
    Ecto.build_assoc(host, :devices) |> changeset(changes)
  end

  def changeset(%Schema{} = device, %{} = params) do
    device
    |> Changeset.cast(params, columns(:cast))
    |> Changeset.validate_required(columns(:required))
    |> Changeset.validate_format(:ident, ~r/^[a-z~]{1,}[[:alnum:]][\w .:-]+[[:alnum:]]$/i)
    |> Changeset.validate_length(:ident, max: 128)
    |> Changeset.validate_format(:family, ~r/^[pwm]|[ds]|[i2c]$/)
    |> Changeset.validate_number(:pios, greater_than_or_equal_to: 1)
  end

  @columns [:id, :ident, :family, :mutable, :pios, :last_seen_at, :updated_at, :inserted_at]
  @not_required [:id, :inserted_at, :updated_at]
  @required Enum.reject(@columns, fn x -> x in @not_required end)

  def columns(:cast), do: @columns
  def columns(:required), do: @required

  # def columns(:required), do: columns_exclude([:inserted_at, :updated_at])
  # def columns(:replace), do: columns_exclude([:last_seen_at, :updated_at])
  #
  # def columns_exclude(cols), do: Enum.reject(@columns_all, fn key -> key in cols end)

  def create(<<_::binary>> = ident, create_at, %{} = params) do
    %{
      ident: ident,
      family: determine_family(ident),
      mutable: params.subsystem == "mut",
      pios: pios_from_pin_data(params.data),
      last_seen_at: create_at
    }
    |> changeset(params.host)
    |> Sally.Repo.insert!(insert_opts())
  end

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

  @dont_replace [:id, :last_seen_at, :updated_at]
  @replace Enum.reject(@columns, fn x -> x in @dont_replace end)
  @insert_opts [on_conflict: {:replace, @replace}, conflict_target: [:ident]] ++ @returned
  def insert_opts, do: @insert_opts

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

  def load_aliases(%Schema{} = device), do: Repo.preload(device, [:aliases])

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
    device = load_aliases(device)

    dev_alias = Enum.find(device.aliases, &match?(%{pio: ^pio}, &1))

    match?(%Sally.DevAlias{}, dev_alias)
  end

  def pios(%Schema{pios: pios}), do: pios

  def pios_from_pin_data(data) do
    case data do
      %{pins: pin_data} -> Enum.count(pin_data)
      _no_pin_data -> 1
    end
  end

  def preload(%Schema{} = x), do: Repo.preload(x, [:aliases])

  def summary(%Schema{} = x), do: Map.take(x, [:ident, :last_seen_at])

  def ttl_reset(%Sally.DevAlias{device_id: id, updated_at: ttl_at}) do
    Sally.Repo.load(Schema, id: id)
    |> Ecto.Changeset.cast(%{last_seen_at: ttl_at}, [:last_seen_at])
    |> Sally.Repo.update!(@returned)
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
