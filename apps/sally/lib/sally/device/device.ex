defmodule Sally.Device do
  @moduledoc """
  Database implementation of Sally.PulseWidth devices
  """

  require Logger
  use Ecto.Schema

  import Ecto.Query, only: [from: 2, where: 3]

  alias Ecto.Changeset

  alias __MODULE__, as: Schema
  alias Sally.{DevAlias, Host, Repo}

  schema "device" do
    field(:ident, :string)
    field(:family, :string)
    field(:mutable, :boolean)
    field(:pios, :integer)
    field(:seen_at, :utc_datetime_usec, virtual: true)

    belongs_to(:host, Host)
    has_many(:aliases, DevAlias, foreign_key: :device_id, preload_order: [asc: :pio])

    timestamps(type: :utc_datetime_usec)
  end

  @returned [returning: true]
  @shift_opts [:years, :months, :days, :hours, :minutes, :seconds, :milliseconds]

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

  def cleanup(opts) do
    cleanup = cleanup(:query, opts) |> Sally.Repo.all()

    Enum.reduce(cleanup, %{}, fn device, acc ->
      deleted_map = Sally.DevAlias.delete(device)

      Sally.Repo.delete(device)

      Map.merge(acc, deleted_map)
    end)
  end

  @cleanup_defaults [months: -6]
  def cleanup(:query, opts) when is_list(opts) do
    shift_opts = Keyword.take(opts, @shift_opts)

    shift_opts = if shift_opts == [], do: @cleanup_defaults, else: shift_opts

    before_dt = Timex.now() |> Timex.shift(shift_opts)

    from(device in __MODULE__,
      where: device.updated_at <= ^before_dt,
      order_by: [desc: :updated_at],
      select: [:id, :ident]
    )
  end

  @columns [:id, :ident, :family, :mutable, :pios, :updated_at, :inserted_at]
  @not_required [:id, :inserted_at, :updated_at]
  @required Enum.reject(@columns, fn x -> x in @not_required end)

  def columns(:cast), do: @columns
  def columns(:required), do: @required

  def create(<<_::binary>> = ident, _create_at, %{} = params) do
    %{
      ident: ident,
      family: family(ident),
      mutable: params.subsystem == "mut",
      pios: pios_from_pin_data(params.data)
    }
    |> changeset(params.host)
    |> Sally.Repo.insert!(insert_opts())
  end

  @families [:ds, :i2c, :pwm]
  def family(what) do
    case what do
      %{ident: ident} -> family(ident)
      x when x in @families -> Atom.to_string(what)
      <<"ds"::utf8, _rest::binary>> -> "ds"
      <<"pwm"::utf8, _rest::binary>> -> "pwm"
      <<"i2c"::utf8, _rest::binary>> -> "i2c"
      _ -> raise("family unsupported: #{inspect(what)}")
    end
  end

  def find(what) do
    {field, val} = what_field(what)

    query = from(device in __MODULE__, where: field(device, ^field) == ^val, order_by: device.ident)

    case field do
      :family ->
        pattern = val <> "%"
        where(query, [device], ilike(device.ident, ^pattern)) |> Sally.Repo.all()

      :mutable ->
        Sally.Repo.all(query)

      _ ->
        Sally.Repo.one(query) |> preload()
    end
  end

  def immutable?(%{mutable: mutable}), do: not mutable

  @dont_replace [:id, :updated_at]
  @replace Enum.reject(@columns, fn x -> x in @dont_replace end)
  @insert_opts [on_conflict: {:replace, @replace}, conflict_target: [:ident]] ++ @returned
  def insert_opts, do: @insert_opts

  @latest_steps [:query, :load, :locate, :finalize]
  # NOTE: this can be a very expensive function!!
  def latest(opts \\ []) do
    schema? = Keyword.get(opts, :schema, false)

    Enum.reduce(@latest_steps, nil, fn
      :query, _ -> latest_query(opts)
      :load, query -> Sally.Repo.all(query)
      :locate, devices -> latest_locate(devices)
      # a device without aliases was found, this is the one we want
      :finalize, %{id: _} = latest -> if(schema?, do: latest, else: latest.ident)
      # bad luck, no device without aliases found
      :finalize, _none -> raise("unable to discover a latest device")
    end)
  end

  def latest_locate(devices) do
    # NOTE: reduce the devices until one is found without aliases
    Enum.reduce_while(devices, :none, fn device, _acc ->
      device = preload(device)

      if match?(%{aliases: []}, device), do: {:halt, device}, else: {:cont, :has_aliases}
    end)
  end

  def latest_query(opts) do
    shifts = Keyword.take(opts, @shift_opts)
    unless shifts != [], do: raise("must provide at least one shift option")

    after_at = Timex.now() |> Timex.shift(shifts)

    from(device in __MODULE__,
      where: device.inserted_at >= ^after_at,
      order_by: device.inserted_at,
      select_merge: %{seen_at: device.updated_at}
    )
  end

  def load_aliases(%Schema{} = device), do: Repo.preload(device, [:aliases])

  # def load_host(device) do
  #   Repo.preload(device, [:host])
  # end

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

  def nature(%Sally.Device{mutable: mutable}), do: if(mutable, do: :cmds, else: :datapoints)

  def oldest(:query) do
    from(device in __MODULE__, order_by: [asc: :updated_at], limit: 1)
  end

  def oldest, do: oldest(:query) |> Sally.Repo.one()

  def pio_check(schema, opts) when is_list(opts) do
    pio = opts[:pio]

    case schema do
      %{mutable: true} when is_integer(pio) -> pio
      %{mutable: false} -> 0
      _ -> raise(":pio option required for mutable device aliases")
    end
  end

  def pio_aliased?(%__MODULE__{pios: pios} = device, pio) do
    unless is_integer(pio), do: raise("pio must be an integer")
    unless pio - 1 < pios, do: raise("pio exceeds device pios (#{pios})")

    Sally.DevAlias.load_aliases(device)
    |> Enum.any?(&match?(%{pio: ^pio}, &1))
  end

  def pios(%Schema{pios: pios}), do: pios

  def pios_from_pin_data(data) do
    case data do
      %{pins: pin_data} -> Enum.count(pin_data)
      _no_pin_data -> 1
    end
  end

  def preload(what) do
    case what do
      %{id: _} -> Sally.Repo.preload(what, aliases: Sally.DevAlias.load_alias_query(what))
      nil -> nil
    end
  end

  def summary(:keys), do: [:ident, :seen_at]

  def ttl_reset(%Sally.DevAlias{device_id: id, updated_at: ttl_at}) do
    Sally.Repo.load(Schema, id: id)
    |> Ecto.Changeset.cast(%{updated_at: ttl_at}, [:updated_at])
    |> Sally.Repo.update!(@returned)
  end

  def what_field(what) do
    case what do
      %__MODULE__{id: id} -> {:id, id}
      %Sally.DevAlias{device_id: device_id} -> {:id, device_id}
      [{:family, x}] -> {:family, family(x)}
      [{field, _val} = tuple] when is_atom(field) -> tuple
      <<_::binary>> -> {:ident, what}
      x when is_integer(x) -> {:id, what}
      _ -> raise("bad args: #{inspect(what)}")
    end
  end
end
