defmodule Sally.DevAlias do
  @moduledoc """
  Database schema definition and functions for the logical representation of
  a specific `Sally.Device` pio.

  All actions (e.g. reading current value, changing state_ on a physical `Sally.Device`
  require a `Sally.DevAlias`
  """
  require Logger
  require Ecto.Query

  use Ecto.Schema
  use Alfred.Status
  use Alfred.Execute, broom: Sally.Command
  use Alfred.JustSaw

  alias __MODULE__, as: Schema
  alias Ecto.Changeset
  alias Sally.{Command, Datapoint, Device, Repo}

  @pio_min 0
  @ttl_default 15_000
  @ttl_min 50

  @type list_or_schema() :: [Ecto.Schema.t(), ...] | Ecto.Schema.t()

  schema "dev_alias" do
    field(:name, :string)
    field(:pio, :integer)
    field(:description, :string, default: "<none>")
    field(:ttl_ms, :integer, default: @ttl_default)

    belongs_to(:device, Device)
    has_many(:cmds, Command, foreign_key: :dev_alias_id, preload_order: [desc: :sent_at])
    has_many(:datapoints, Datapoint, foreign_key: :dev_alias_id, preload_order: [desc: :reading_at])

    timestamps(type: :utc_datetime_usec)
  end

  def align_status(%{aliases: [_ | _] = aliases, data: %{pins: _} = data, seen_at: seen_at}) do
    Enum.reduce(aliases, Ecto.Multi.new(), fn dev_alias, multi ->
      multi_name = String.to_atom("aligned_#{dev_alias.pio}")

      case align_status_one(dev_alias, data, seen_at) do
        %Ecto.Changeset{} = cs -> Ecto.Multi.insert(multi, multi_name, cs, returning: true)
        :no_change -> multi
      end
    end)
  end

  def align_status(_changes), do: Ecto.Multi.new()

  def align_status_one(%{pio: pio} = dev_alias, %{pins: pins}, seen_at) do
    pin_cmd = Enum.reduce(pins, :no_pin, fn [pin, cmd], acc -> if(pin == pio, do: cmd, else: acc) end)

    case status(dev_alias, nature: :cmds) do
      status when pin_cmd == :no_pin ->
        cmd_mismatch(status, "bad_pin")

      %{rc: :pending} ->
        :no_change

      %{rc: :ok, detail: %{cmd: ^pin_cmd}} ->
        :no_change

      # NOTE: special case when DevAlias doesn't have any commands yet
      %{rc: :error} ->
        Command.reported_cmd_changeset(dev_alias, pin_cmd, seen_at)

      status ->
        cmd_mismatch(status, pin_cmd)
        Command.reported_cmd_changeset(dev_alias, pin_cmd, seen_at)
    end
  end

  defp cmd_mismatch(%Alfred.Status{} = status, pin_cmd) do
    [
      module: Sally.Command,
      align_status: true,
      mismatch: true,
      reported_cmd: pin_cmd,
      local_cmd: Alfred.Status.get_cmd(status),
      status_error: status.rc,
      name: status.name
    ]
    |> Betty.app_error_v2()

    :no_change
  end

  defp cmd_mismatch(status, pin_cmd) do
    [pin_cmd, "\n", inspect(status, pretty: true)] |> Logger.warn()

    :no_change
  end

  def add_datapoint(repo, %{aliases: dev_aliases}, raw_data, %DateTime{} = reading_at)
      when is_map(raw_data) do
    for %Schema{} = schema <- dev_aliases, reduce: {:ok, []} do
      {:ok, acc} ->
        case Datapoint.add(repo, schema, raw_data, reading_at) do
          {:ok, %Datapoint{} = x} -> {:ok, [x] ++ acc}
          {:error, _reason} = rc -> rc
        end
    end
  end

  def changeset(changes) when is_list(changes) do
    {id, changes_rest} = Keyword.pop(changes, :id)
    required = Keyword.keys(changes)

    Enum.into(changes_rest, %{})
    |> changeset(struct(__MODULE__, id: id), required: required)
  end

  def changeset(changes, %Schema{} = a, opts \\ []) do
    required = opts[:required] || columns(:required)

    a
    |> Changeset.cast(changes, columns(:cast))
    |> Changeset.validate_required(required)
    |> Changeset.validate_format(:name, ~r/^[a-z~][\w .:-]+[[:alnum:]]$/i)
    |> Changeset.validate_length(:name, max: 128)
    |> Changeset.validate_number(:pio, greater_than_or_equal_to: @pio_min)
    |> Changeset.validate_length(:description, max: 128)
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

  def create(%Device{} = device, opts) do
    dev_alias = Ecto.build_assoc(device, :aliases)

    %{
      name: opts[:name],
      pio: opts[:pio],
      description: opts[:description] || dev_alias.description,
      ttl_ms: opts[:ttl_ms] || dev_alias.ttl_ms
    }
    |> changeset(dev_alias)
    |> Repo.insert(on_conflict: {:replace, columns(:replace)}, returning: true, conflict_target: [:name])
  end

  def delete(name_or_id) do
    with %Schema{} = a <- find(name_or_id) |> load_command_ids() |> load_datapoint_ids(),
         {:ok, cmd_count} <- Command.purge(a, :all),
         {:ok, dp_count} <- Datapoint.purge(a, :all),
         {:ok, %Schema{name: n}} <- Repo.delete(a) do
      res = [name: n, commands: cmd_count, datapoints: dp_count] |> Enum.reject(fn x -> x == 0 end)

      {:ok, res}
    else
      nil -> {:unknown, name_or_id}
      error -> error
    end
  end

  @doc """
  Get the `Sally.Device` id from a `DevAlias` or list of `DevAlias`
  """
  @spec device_id(list_or_schema) :: pos_integer()
  def device_id([%Schema{} = x | _]), do: device_id(x)
  def device_id(%Schema{device_id: x}), do: x

  def exists?(name_or_id) do
    case find(name_or_id) do
      %Schema{} -> true
      _anything -> false
    end
  end

  @doc false
  def execute_cmd(%Alfred.Status{} = status, opts), do: Alfred.Status.raw(status) |> execute_cmd(opts)

  def execute_cmd(%Sally.DevAlias{} = dev_alias, opts) do
    new_cmd = Sally.Command.add_v2(dev_alias, opts)

    rc = if(new_cmd.acked, do: :ok, else: :pending)

    preloads = [dev_alias: [device: [:host]]]
    Sally.Repo.preload(new_cmd, preloads) |> Sally.Payload.send_cmd_v2(opts)

    {rc, new_cmd}
  end

  @doc """
  SQL Explain for status queries
  """
  @spec explain(name :: String.t(), :status, opts :: list()) :: :ok
  def explain(name, :status, what, opts \\ [analyze: true, buffers: true]) do
    {analyze, query_opts} = Keyword.pop(opts, :analyze, true)

    explain_opts = [analyze: analyze]

    case what do
      :cmds -> Sally.Command
      :datapoints -> Sally.Datapoint
    end
    |> tap(fn module -> ["\n", inspect(module), ".status_query/2\n"] |> IO.puts() end)
    |> then(fn module -> module.status_query(name, query_opts) end)
    |> then(fn query -> Sally.Repo.explain(:all, query, explain_opts) end)
    |> String.split("\n")
    |> Enum.each(fn line -> [line] |> IO.puts() end)
  end

  # (1 of 2) find with proper opts
  def find(opts) when is_list(opts) and opts != [] do
    case Repo.get_by(Schema, opts) do
      %Schema{} = x -> load_device(x) |> load_cmd_last()
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

  def find_by_name(name) when is_binary(name), do: find(name: name)

  # def for_pio?(%Schema{pio: alias_pio}, pio), do: alias_pio == pio

  # @doc """
  #   Mark a list of DevAlias as just seen within an Ecto.Multi sequence
  #
  #   Returns:
  #   ```
  #   {:ok, [%DevAlias{} | []]}  # success
  #   {:error, error}            # update failed for one DevAlias
  #   ```
  #
  # """
  # @doc since: "0.5.10"
  # @type multi_changes :: %{aliases: [Ecto.Schema.t(), ...]}
  # @type ok_tuple :: {:ok, Ecto.Schema.t()}
  # @type error_tuple :: {:error, any()}
  # @type db_result :: ok_tuple() | error_tuple()
  # @spec just_saw(Ecto.Repo.t(), multi_changes(), DateTime.t()) :: db_result()
  # def just_saw(repo, %{aliases: schemas}, %DateTime{} = seen_at) when is_list(schemas) do
  #   for %Schema{} = schema <- schemas, reduce: {:ok, []} do
  #     {:ok, acc} ->
  #       cs = changeset(%{updated_at: seen_at}, schema)
  #
  #       case repo.update(cs, returning: true) do
  #         {:ok, %Schema{} = x} -> {:ok, [x | acc]}
  #         {:error, error} -> {:error, error}
  #       end
  #
  #     {:error, _} = acc ->
  #       acc
  #   end
  # end

  def just_saw_db(%{} = multi_changes) do
    %{device: %{id: device_id}, seen_at: seen_at} = multi_changes

    Ecto.Query.from(dev_alias in Sally.DevAlias,
      update: [set: [updated_at: ^seen_at]],
      where: [device_id: ^device_id],
      select: [:id, :name, :ttl_ms, :updated_at]
    )
  end

  # @doc """
  #   Mark a single DevAlias (by id) as just seen
  #
  #   Looks up the DevAlias by id then reuses `just_saw/3`
  # """
  # @doc since: "0.5.10"
  # @spec just_saw_id(Ecto.Repo.t(), multi_changes, id :: integer, DateTime.t()) :: db_result()
  # def just_saw_id(repo, _changes, id, %DateTime{} = seen_at) when is_integer(id) do
  #   case repo.get(Schema, id) do
  #     %Schema{} = x -> just_saw(repo, %{aliases: [x]}, seen_at)
  #     x when is_nil(x) -> just_saw(repo, %{aliases: []}, seen_at)
  #   end
  # end

  def load_aliases(repo, multi_changes) do
    %{device: %{id: device_id}} = multi_changes

    Ecto.Query.from(a in Schema, where: [device_id: ^device_id], order_by: [asc: a.pio])
    |> then(fn query -> {:ok, repo.all(query)} end)
  end

  def load_cmd_last(%Schema{} = x) do
    cmd_query = Command.query_preload_latest_cmd()
    Repo.preload(x, cmds: cmd_query)
  end

  # def load_alias_with_last_cmd(name) when is_binary(name) do
  #   cmd_q = Command.query_preload_latest_cmd()
  #
  #   Ecto.Query.from(a in Schema,
  #     where: a.name == ^name,
  #     order_by: [asc: a.pio],
  #     preload: [cmds: ^cmd_q, device: []]
  #   )
  #   |> Repo.one()
  # end

  # def load_aliases_with_last_cmd(repo, %{device: device} = _multi_changes) do
  #   import Ecto.Query, only: [from: 2]
  #
  #   # cmd_query = Command.query_preload_latest_cmd()
  #
  #   # NOTE: do not preload cmds here to avoid database performance hit
  #   all_query =
  #     from(a in Schema,
  #       where: [device_id: ^device.id],
  #       order_by: [asc: a.pio]
  #       #  preload: [cmds: ^cmd_query]
  #     )
  #
  #   # NOTE: rather, preload each DevAlias separately for max performance
  #   for %Schema{} = schema <- repo.all(all_query) do
  #     cmd_q = Command.query_preload_latest_cmd(schema.id)
  #     repo.preload(schema, cmds: cmd_q)
  #   end
  #   |> then(fn dev_aliases -> {:ok, dev_aliases} end)
  # end

  defp load_command_ids(schema_or_nil) do
    q = Ecto.Query.from(c in Command, select: [:id])
    Repo.preload(schema_or_nil, [cmds: q], force: true)
  end

  defp load_datapoint_ids(schema_or_nil) do
    q = Ecto.Query.from(dp in Datapoint, select: [:id])
    Repo.preload(schema_or_nil, [datapoints: q], force: true)
  end

  def load_device(schema_or_tuple) do
    case schema_or_tuple do
      {:ok, %Schema{} = a} -> {:ok, Repo.preload(a, [:device])}
      %Schema{} = a -> Repo.preload(a, [:device])
      x -> x
    end
  end

  def load_info(%Schema{} = schema) do
    schema |> Repo.preload(device: [:host]) |> load_cmd_last()
  end

  def mark_updated(%{} = multi_changes, source_key) do
    %{:seen_at => seen_at, ^source_key => source} = multi_changes

    case source do
      %{dev_alias_id: id} -> changeset(id: id, updated_at: seen_at)
    end
  end

  def names do
    Ecto.Query.from(x in Schema, select: x.name, order_by: x.name) |> Repo.all()
  end

  def names_begin_with(pattern) when is_binary(pattern) do
    like_string = "#{pattern}%"

    Ecto.Query.from(x in Schema, where: like(x.name, ^like_string), order_by: x.name, select: x.name)
    |> Repo.all()
  end

  def rename(opts) when is_list(opts) do
    with {:opts, from} when is_binary(from) <- {:opts, opts[:from]},
         {:opts, to} when is_binary(to) <- {:opts, opts[:to]},
         {:found, %Schema{} = x} <- {:found, find_by_name(from)},
         cs <- changeset(%{name: to}, x, [:name]),
         {:ok, %Schema{} = updated_schema} <- Repo.update(cs, returning: true) do
      updated_schema
    else
      {:opts, _} -> {:bad_args, opts}
      {:found, nil} -> {:not_found, opts[:from]}
      {:error, %Changeset{} = cs} -> {:name_taken, cs.changes.name}
    end
  end

  def status_lookup(%{name: name, nature: nature}, opts) do
    case nature do
      :cmds -> Sally.Command.status(name, opts)
      :datapoints -> Sally.Datapoint.status(name, opts)
    end
    |> status_lookup_finalize()
  end

  @doc false
  def status_lookup_finalize(dev_alias) do
    case dev_alias do
      %{cmds: %Ecto.Association.NotLoaded{}} -> struct(dev_alias, cmds: [])
      %{datapoints: %Ecto.Association.NotLoaded{}} -> struct(dev_alias, datapoints: [])
      other -> other
    end
  end

  def summary(%Schema{} = x), do: Map.take(x, [:name, :pio, :description, :ttl_ms])
end
