defmodule PulseWidth.DB.Alias do
  @moduledoc """
  Database implementation of PulseWidth Aliases
  """
  require Logger
  use Ecto.Schema
  use Timex

  alias PulseWidth.DB.Alias, as: Schema
  alias PulseWidth.DB.{Command, Device}
  alias PulseWidth.Payload

  require Ecto.Query
  alias Ecto.Query

  @pio_min 0
  @ttl_default 2000
  @ttl_min 50

  schema "pwm_alias" do
    field(:name, :string)
    field(:device_id, :integer)
    field(:cmd, :string, default: "unknown")
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

  def apply_changes(%Schema{} = a, changes) do
    changeset(a, changes) |> Repo.update(returning: true)
  end

  # (1 of 2) convert parms into a map
  def changeset(%Schema{} = a, p) when is_list(p), do: changeset(a, Enum.into(p, %{}))

  # (2 of 2) params are a map
  def changeset(%Schema{} = a, p) when is_map(p) do
    alias Common.DB
    alias Ecto.Changeset

    a
    |> Changeset.cast(p, columns(:cast))
    |> Changeset.validate_required(columns(:required))
    |> Changeset.validate_length(:name, min: 3, max: 32)
    |> Changeset.validate_format(:name, DB.name_regex())
    |> Changeset.validate_length(:description, max: 50)
    |> Changeset.validate_length(:cmd, max: 32)
    |> Changeset.validate_number(:pio, greater_than_or_equal_to: @pio_min)
    |> Changeset.validate_number(:ttl_ms, greater_than_or_equal_to: @ttl_min)
    |> Changeset.unique_constraint(:name, [:name])
  end

  # helpers for changeset columns
  def columns(:all) do
    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
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
    case Repo.get_by(Schema, opts) do
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

  def load_cmd_last(%Schema{} = a) do
    Repo.preload(a, cmds: Query.from(d in Command, order_by: [desc: d.inserted_at], limit: 1))
  end

  def load_device(%Schema{} = a), do: Repo.preload(a, [:device])

  def names do
    Query.from(x in Schema, select: x.name, order_by: x.name) |> Repo.all()
  end

  def names_begin_with(pattern) when is_binary(pattern) do
    like_string = [pattern, "%"] |> IO.iodata_to_binary()

    Query.from(x in Schema, where: like(x.name, ^like_string), order_by: x.name, select: x.name) |> Repo.all()
  end

  def preload(%Schema{} = x) do
    Repo.preload(x, [:device]) |> preload_cmd_last()
  end

  def preload_cmd_last(%Schema{} = x) do
    Repo.preload(x, cmds: Query.from(d in Command, order_by: [desc: d.inserted_at], limit: 1))
  end

  def preload_unacked_cmds(%Schema{} = x) do
    Repo.preload(x, cmds: Query.from(c in Command, where: c.acked == false))
  end

  # def record_cmd(%Schema{name: name} = a, cmd_map, opts) do

  def record_cmd(name, cmd_map, opts) do
    # load the record the cmd is associated with
    a = find(name)

    # add the command and put the name in the result map for upstream
    result_map = Command.add(a, cmd_map, opts) |> put_in([:name], name)

    # NOTE! create anonymous fn HERE to capture result_map for updating
    add_to_result = fn [{k, v}] -> put_in(result_map, [k], v) end

    case result_map do
      # downstream supplied the cmd, update to align
      %{cmd_rc: {:ok, _}, cmd_acked: rcmd} ->
        [alias_rc: update_cmd(a, rcmd)] |> add_to_result.()

      # send the cmd_map including the newly inserted cmd refid
      %{cmd_rc: {:ok, new_cmd}} ->
        pub_opts = [opts, refid: new_cmd.refid] |> List.flatten()

        # ensure the device association is loaded for Payload.send_cmd/3
        [pub_rc: load_device(a) |> Payload.send_cmd(cmd_map, pub_opts)] |> add_to_result.()

      # something went wrong, let the caller sort it
      error ->
        error
    end
  end

  def status(%Schema{} = a, opts) do
    %Schema{
      cmd: cmd,
      name: name,
      device: %Device{last_seen_at: seen_at},
      cmds: cmds,
      updated_at: at,
      ttl_ms: ttl_ms
    } = load_device(a) |> load_cmd_last()

    status = %{cmd: cmd, at: at}

    %{name: name, seen_at: seen_at, ttl_ms: opts[:ttl_ms] || ttl_ms}
    |> put_in([:cmd_reported], status)
    |> Command.status(cmds)
    |> ttl_check()
  end

  def status(x, _opts), do: %{not_found: true, invalid: inspect(x, pretty: true)}

  defp update_cmd(%Schema{} = a, rcmd) do
    a
    |> changeset(%{cmd: rcmd})
    |> Repo.update(returning: true)
  end

  def upsert(p) when is_map(p) do
    changes = Map.take(p, columns(:all))
    cs = changeset(%Schema{}, changes)

    opts = [on_conflict: {:replace, columns(:replace)}, returning: true, conflict_target: [:name]]

    case Repo.insert(cs, opts) do
      {:ok, %Schema{}} = rc -> rc
      {:error, e} -> {:error, inspect(e, pretty: true)}
    end
  end

  defp ttl_check(%{ttl_ms: ttl_ms, seen_at: seen_at} = m) do
    # diff = DateTime.utc_now() |> DateTime.diff(seen_at, :millisecond)

    ttl_dt = Timex.now() |> Timex.shift(milliseconds: ttl_ms * -1)

    if Timex.before?(seen_at, ttl_dt), do: put_in(m, [:ttl_expired], true), else: m
  end
end
