defmodule Switch.DB.Alias do
  @moduledoc false

  require Logger
  use Ecto.Schema

  alias Switch.DB.Alias, as: Schema
  alias Switch.DB.{Command, Device}

  @pio_min 0
  @ttl_default 60_000
  @ttl_min 1

  schema "switch_alias" do
    field(:name, :string)
    field(:device_id, :integer)
    field(:remote_cmd, :string, default: "unknown")
    field(:description, :string, default: "<none>")
    field(:pio, :integer)
    field(:ttl_ms, :integer, default: @ttl_default)

    belongs_to(:device, Device,
      source: :device_id,
      references: :id,
      foreign_key: :device_id,
      define_field: false
    )

    has_many(:cmds, Command,
      references: :id,
      foreign_key: :alias_id
    )

    timestamps(type: :utc_datetime_usec)
  end

  # def active_cmd(%Schema{} = x) do
  #   case preload(x) do
  #     %Schema{cmds: cmds} = x -> {x, Command.active_cmd(cmds)}
  #     x -> {x, :unknown}
  #   end
  # end

  def apply_reported_cmd(%Schema{} = a, cmd) do
    import Command, only: [map_cmd: 1]
    changeset(a, remote_cmd: map_cmd(cmd)) |> Repo.update(returning: true)
  end

  # unique to this schema
  def assemble_state(%Schema{pio: pio} = a) do
    %{pio: pio, state: nil} |> map_cmd_for_state(a)
  end

  # (1 of 2) convert parms into a map
  def changeset(%Schema{} = a, p) when is_list(p), do: changeset(a, Enum.into(p, %{}))

  # (2 of 2) params are a map
  def changeset(%Schema{} = a, p) when is_map(p) do
    alias Ecto.Changeset
    import Common.DB, only: [name_regex: 0]

    a
    |> Changeset.cast(p, columns(:cast))
    |> Changeset.validate_required(columns(:required))
    |> Changeset.validate_format(:name, name_regex())
    |> Changeset.validate_inclusion(:remote_cmd, ["off", "on", "unknown"])
    |> Changeset.validate_number(:pio, greater_than_or_equal_to: @pio_min)
    |> Changeset.validate_number(:ttl_ms, greater_than_or_equal_to: @ttl_min)
    |> Changeset.unique_constraint(:name, [:name])
  end

  # helpers for changeset columns
  def columns(:all) do
    import List, only: [flatten: 1]
    import Map, only: [drop: 2, from_struct: 1, keys: 1]

    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> flatten()

    %Schema{} |> from_struct() |> drop(these_cols) |> keys() |> flatten()
  end

  def columns(:cast), do: columns(:all)
  def columns(:required), do: columns_all(only: [:device_id, :name, :pio])
  def columns(:replace), do: columns_all(drop: [:name, :inserted_at])

  def columns_all(opts) when is_list(opts) do
    keep_set = MapSet.new(opts[:only] || columns(:all))
    drop_set = MapSet.new(opts[:drop] || columns(:all))

    MapSet.difference(keep_set, drop_set) |> MapSet.to_list()
  end

  def create(%Device{id: id}, name, pio, opts \\ []) when is_binary(name) and is_list(opts) do
    %{
      device_id: id,
      name: name,
      pio: pio,
      description: opts[:description] || "<none>",
      ttl_ms: opts[:ttl_ms] || @ttl_default
    }
    |> upsert()
  end

  def delete(name_or_id) do
    with %Schema{} = x <- find(name_or_id),
         {:ok, %Schema{name: n}} <- Repo.delete(x) do
      {:ok, n}
    else
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
    import Repo, only: [get_by: 2]

    case get_by(Schema, opts) do
      %Schema{} = x -> preload(x)
      x when is_nil(x) -> nil
    end
  end

  # (2 of 2) validate param and build opts for find/2
  def find(id_or_device) do
    case id_or_device do
      x when is_binary(x) -> find(name: x)
      x when is_integer(x) -> find(id: x)
      x -> {:bad_args, "must be binary or integer: #{inspect(x)}"}
    end
  end

  def for_pio?(%Schema{pio: alias_pio}, pio), do: alias_pio == pio

  def load_last_cmd(%Schema{} = a) do
    import Ecto.Query, only: [from: 2]

    Repo.preload(a, cmds: from(d in Command, order_by: [desc: d.inserted_at], limit: 1))
  end

  def load_device(%Schema{} = a), do: Repo.preload(a, [:device])

  # unique to this schema
  def map_cmd_for_state(base, %Schema{remote_cmd: cmd}) do
    map_cmd_fn = fn
      x when x in ["off", :off, "unknown", :unknown] -> put_in(base.state, false)
      x when x in ["on", :on] -> put_in(base.state, true)
    end

    map_cmd_fn.(cmd)
  end

  def names do
    import Ecto.Query, only: [from: 2]

    from(x in Schema, select: x.name, order_by: x.name) |> Repo.all()
  end

  def names_begin_with(pattern) when is_binary(pattern) do
    import Ecto.Query, only: [from: 2]

    like_string = [pattern, "%"] |> IO.iodata_to_binary()

    from(x in Schema, where: like(x.name, ^like_string), order_by: x.name, select: x.name) |> Repo.all()
  end

  def preload(%Schema{} = x) do
    Repo.preload(x, [:device]) |> preload_last_cmd()
  end

  def preload_last_cmd(%Schema{} = x) do
    import Ecto.Query, only: [from: 2]

    Repo.preload(x, cmds: from(d in Command, order_by: [desc: d.inserted_at], limit: 1))
  end

  def preload_unacked_cmds(%Schema{} = x) do
    import Ecto.Query, only: [from: 2]

    Repo.preload(x, cmds: from(c in Command, where: c.acked == false))
  end

  def record_cmd(%Schema{name: name} = a, cmd, opts) do
    import Command, only: [add: 3]
    import Switch.Payload, only: [send_cmd: 3]

    # send_cmd needs the device
    a = load_device(a)

    # add the command, then send the payload
    case add(a, cmd, opts) do
      %{cmd: {:ok, %Command{refid: refid}}} ->
        pub_rc = send_cmd(a, cmd, opts ++ [refid: refid])
        {:pending, [name: name, cmd: cmd[:cmd], refid: refid, pub_rc: pub_rc]}

      %{cmd: {_, _} = rc} ->
        {:failed, {:add_cmd, rc}}

      error ->
        {:record_cmd_failed, error}
    end
  end

  # unique to this Schema
  def status(%Schema{} = a, opts) do
    import Helen.Time.Helper, only: [ttl_check: 1]
    import Command, only: [map_cmd: 1]

    %Schema{
      remote_cmd: remote_cmd,
      name: name,
      device: %Device{last_seen_at: seen_at},
      cmds: cmds,
      updated_at: at,
      ttl_ms: ttl_ms
    } = load_device(a) |> load_last_cmd()

    status = %{cmd: map_cmd(remote_cmd), at: at}

    %{name: name, seen_at: seen_at, ttl_ms: opts[:ttl_ms] || ttl_ms}
    |> put_in([:remote_cmd], status)
    |> Command.status(cmds)
    |> ttl_check()
  end

  def status(x, _opts), do: %{not_found: true, invalid: inspect(x, pretty: true)}

  def upsert(p) when is_map(p) do
    cs = changeset(%Schema{}, Map.take(p, columns(:all)))

    opts = [on_conflict: {:replace, columns(:replace)}, returning: true, conflict_target: [:name]]

    case Repo.insert(cs, opts) do
      {:ok, %Schema{}} = rc -> rc
      {:error, e} -> {:error, inspect(e, pretty: true)}
    end
  end
end
