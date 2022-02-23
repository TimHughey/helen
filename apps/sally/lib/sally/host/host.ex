defmodule Sally.Host do
  require Logger

  use Ecto.Schema
  import Ecto.Query, only: [from: 2]

  schema "host" do
    field(:ident, :string)
    field(:name, :string)
    field(:profile, :string, default: "generic")
    field(:authorized, :boolean, default: false)
    field(:firmware_vsn, :string)
    field(:idf_vsn, :string)
    field(:app_sha, :string)
    field(:build_at, :utc_datetime_usec)
    field(:start_at, :utc_datetime_usec)
    field(:reset_reason, :string)
    field(:seen_at, :utc_datetime_usec)
    field(:instruct, :any, virtual: true, default: :none)

    has_many(:devices, Sally.Device, references: :id, foreign_key: :host_id)

    timestamps(type: :utc_datetime_usec)
  end

  @profiles :profiles
  @returned [returning: true]

  def authorize(%__MODULE__{} = host, val) when is_boolean(val) do
    changes = %{authorized: val}

    changeset(host, changes) |> Sally.Repo.update!(@returned)
  end

  @begins_fields [:ident, :name]
  @begins_error "field must :ident or :name"
  def begins_with(<<_::binary>> = pattern, field \\ :ident) do
    unless field in @begins_fields, do: raise(@begins_error)

    begins_with_query(pattern, field) |> Sally.Repo.all()
  end

  def begins_with_query(<<_::binary>> = pattern, want_field) do
    like_string = pattern <> "%"

    from(host in __MODULE__,
      where: field(host, ^want_field) |> ilike(^like_string),
      order_by: field(host, ^want_field),
      select: field(host, ^want_field)
    )
  end

  @meta "meta"
  @payload_drop ["description"]
  def boot_payload(%{profile: profile}) do
    # NOTE:
    #  1. drop unnecessary metadata
    #  2. we reuse the changeset validator which returns an error list
    case profile_data(profile) do
      %{@meta => meta} = data -> Map.put(data, @meta, Map.drop(meta, @payload_drop))
      [{:profile, {_, [additional: reason]}}] -> raise(reason)
    end
  end

  # NOTE: used by Sally.Host.Dispatch.process/1
  @doc false
  def changeset(%{} = changes) do
    required_keys = Map.keys(changes)
    changeset(%__MODULE__{}, changes, required_keys)
  end

  @doc false
  def changeset(%__MODULE__{} = host, %{} = changes) do
    changeset(host, changes, Map.keys(changes))
  end

  # (2 of 2) traditional implementation accepting a Schema, changes and what's required
  @ident_regex ~r/^[a-z]+[.][[:alnum:]]{3,}$/i
  @name_regex ~r/^[a-z~][\w .:-]+[[:alnum:]]$/i
  @profile_regex ~r/^[a-z]+[\w.-]+$/i
  @doc false
  def changeset(%__MODULE__{} = schema, changes, required) do
    schema
    |> Ecto.Changeset.cast(changes, required)
    |> Ecto.Changeset.validate_required(required)
    |> Ecto.Changeset.validate_format(:ident, @ident_regex)
    |> Ecto.Changeset.validate_length(:ident, max: 24)
    |> Ecto.Changeset.validate_format(:name, @name_regex)
    |> Ecto.Changeset.validate_length(:name, max: 32)
    |> Ecto.Changeset.validate_format(:profile, @profile_regex)
    |> Ecto.Changeset.validate_length(:profile, max: 32)
    |> Ecto.Changeset.validate_change(:profile, &profile_exists/2)
    |> Ecto.Changeset.validate_length(:firmware_vsn, max: 32)
    |> Ecto.Changeset.validate_length(:idf_vsn, max: 12)
    |> Ecto.Changeset.validate_length(:app_sha, max: 12)
    |> Ecto.Changeset.validate_length(:reset_reason, max: 24)
  end

  @doc false
  def changeset_constrain_name(%__MODULE__{} = host, changes) do
    required = Map.keys(changes)
    changeset(host, changes, required) |> Ecto.Changeset.unique_constraint(:name)
  end

  def deauthorize(%__MODULE__{} = host), do: authorize(host, false)

  def find_by(opts) when is_list(opts), do: Sally.Repo.get_by(__MODULE__, opts)

  @doc false
  def insert_opts(replace_cols) when is_list(replace_cols) do
    [on_conflict: {:replace, replace_cols}, conflict_target: [:ident]] ++ @returned
  end

  def latest(opts) when is_list(opts) do
    latest_query(opts) |> Sally.Repo.all()
  end

  @latest_default [hours: -1]
  def latest_defaults, do: @latest_default

  @latest_shift_opts [:weeks, :days, :hours, :minutes, :seconds]
  def latest_query(opts) when is_list(opts) do
    since_dt = since_dt(opts, @latest_shift_opts, latest_defaults())

    from(host in __MODULE__,
      where: host.ident == host.name,
      where: host.authorized == false,
      where: host.reset_reason != "retired",
      where: host.inserted_at >= ^since_dt,
      order_by: [desc: host.inserted_at]
    )
  end

  @live_default [minutes: -2]
  def live_defaults, do: @live_default

  def live(opts) when is_list(opts) do
    live_query(opts) |> Sally.Repo.all()
  end

  @live_shift_opts [:minutes, :seconds]
  def live_query(opts) when is_list(opts) do
    since_dt = since_dt(opts, @live_shift_opts, live_defaults())

    from(host in __MODULE__, where: host.seen_at >= ^since_dt, order_by: [asc: host.name])
  end

  @ota_defaults [want: :latest]
  def ota_defaults, do: @ota_defaults

  @ota_send_opts [filters: ["ota"]]
  @firmware {__MODULE__, :firmware}
  def ota(%{ident: ident} = host, opts) do
    opts = Keyword.merge(@ota_defaults, opts)

    firmware = Sally.Config.file_locate(@firmware, opts)

    case firmware do
      <<_::binary>> ->
        send_opts = Keyword.merge(@ota_send_opts, ident: ident, data: %{file: firmware}, opts: opts)

        struct(host, instruct: Sally.Host.Instruct.send(send_opts))
    end
  end

  def profile(%__MODULE__{} = host, <<_::binary>> = profile) do
    changes = %{profile: profile}
    changeset(host, changes) |> Sally.Repo.update(@returned)
  end

  @doc false
  def profile_exists(:profile, profile) do
    case profile_data(profile) do
      %{} -> []
      error -> error
    end
  end

  @profile_error "profile error"
  def profile_data(<<_::binary>> = profile_name) do
    profiles_path = Sally.Config.path_get({__MODULE__, @profiles})
    file = [profiles_path, profile_name <> ".toml"] |> Path.join()

    decode = Toml.decode_file(file, filename: file)

    # NOTE: this used as a changeset validator so return an error list
    case decode do
      {:ok, %{} = map} -> map
      {:error, reason} -> [profile: {@profile_error, [additional: reason]}]
    end
  end

  def rename(%__MODULE__{} = host, <<_::binary>> = to) do
    cs = changeset_constrain_name(host, %{name: to})
    updated = Sally.Repo.update(cs, @returned)

    case updated do
      {:ok, host} -> host
      {:error, %Ecto.Changeset{}} -> {:name_taken, to}
      {:error, _} -> updated
    end
  end

  def retire(%__MODULE__{} = host) do
    name = "retired " <> host.name
    changes = %{authorized: false, name: name, reset_reason: "retired"}

    changeset(host, changes) |> Sally.Repo.update!(@returned)
  end

  @restart_opts [subsystem: "host", filters: ["restart"]]
  def restart(%{ident: ident} = host, opts) do
    send_opts = Keyword.merge(@restart_opts, ident: ident, opts: opts)
    instruct = Sally.Host.Instruct.send(send_opts)

    struct(host, instruct: instruct)
  end

  def setup(%__MODULE__{} = host, opts) do
    changes = Enum.into(opts, %{authorized: true})

    changeset(host, changes) |> Sally.Repo.update(@returned)
  end

  @doc false
  def since_dt(opts, shift_opts, default_shift_opts) do
    ref_dt = Keyword.get(opts, :ref_dt, Timex.now())
    shift_opts = Keyword.take(opts, shift_opts)

    shift_opts = if shift_opts == [], do: default_shift_opts, else: shift_opts

    Timex.shift(ref_dt, shift_opts)
  end

  @summary_keys [:name, :ident, :profile, :seen_at]
  def summary(%__MODULE__{} = host) do
    Map.take(host, @summary_keys)
  end

  @unnamed_default [years: -10]
  def unnamed_defaults, do: @unnamed_default

  def unnamed(opts) when is_list(opts) do
    unnamed_query(opts) |> Sally.Repo.all()
  end

  @unnamed_shift_opts [:years, :months, :days, :hours, :minutes, :seconds]
  def unnamed_query(opts) do
    since_dt = since_dt(opts, @unnamed_shift_opts, unnamed_defaults())

    from(host in __MODULE__,
      where: host.ident == host.name,
      where: host.start_at >= ^since_dt,
      order_by: [desc: :start_at]
    )
  end
end
