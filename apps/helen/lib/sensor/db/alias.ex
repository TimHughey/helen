defmodule Sensor.DB.Alias do
  @moduledoc """
  Database functionality for Sensor Alias
  """

  use Ecto.Schema

  alias Sensor.DB.Alias, as: Schema
  alias Sensor.DB.{DataPoint, Device}

  require Ecto.Query
  alias Ecto.Query

  @ttl_default_ms 60_000
  @ttl_min 1

  schema "sensor_alias" do
    field(:name, :string)
    field(:description, :string, default: "<none>")
    field(:ttl_ms, :integer, default: @ttl_default_ms)

    belongs_to(:device, Device)
    has_many(:datapoints, DataPoint)

    timestamps(type: :utc_datetime_usec)
  end

  # def apply_changes(%Schema{} = a, changes) do
  #   changeset(a, changes) |> Repo.update(returning: true)
  # end

  def assign_device(%Schema{} = a, %Device{} = device) do
    changes = %{device_id: device.id}

    case changeset(a, changes) |> Repo.update(returning: true) do
      {:ok, %Schema{} = revised} -> {:ok, [name: revised.name, device: revised.device]}
      error -> error
    end
  end

  # (1 of 2) convert parms into a map
  # def changeset(%Schema{} = a, p) when is_list(p), do: changeset(a, Enum.into(p, %{}))

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
    |> Changeset.validate_number(:ttl_ms, greater_than_or_equal_to: @ttl_min)
    |> Changeset.unique_constraint(:name, [:name])
  end

  # helpers for changeset columns
  def columns(:all) do
    these_cols = [:__meta__, __schema__(:associations), __schema__(:primary_key)] |> List.flatten()

    %Schema{} |> Map.from_struct() |> Map.drop(these_cols) |> Map.keys() |> List.flatten()
  end

  def columns(:cast), do: columns(:all)
  def columns(:required), do: columns_all(only: [:device_id, :name])
  def columns(:replace), do: columns_all(drop: [:name, :inserted_at])

  def columns_all(opts) when is_list(opts) do
    keep_set = MapSet.new(opts[:only] || columns(:all))
    drop_set = MapSet.new(opts[:drop] || columns(:all))

    MapSet.difference(keep_set, drop_set) |> MapSet.to_list()
  end

  def create(%Device{id: id}, name, opts \\ []) when is_binary(name) and is_list(opts) do
    %{
      device_id: id,
      name: name,
      description: opts[:description] || "<none>",
      ttl_ms: opts[:ttl_ms] || @ttl_default_ms
    }
    |> upsert()
  end

  def delete(name_or_id) do
    with %Schema{} = a <- find(name_or_id) |> load_datapoint_ids(),
         {:ok, count} <- DataPoint.purge(a, :all),
         {:ok, %Schema{name: n}} <- Repo.delete(a) do
      {:ok, [name: n, datapoints: count]}
    else
      nil -> {:unknown, name_or_id}
      error -> error
    end
  end

  def device_name(%Schema{} = a), do: load_device(a).device.device

  def exists?(name_or_id) do
    case find(name_or_id) do
      %Schema{} -> true
      _anything -> false
    end
  end

  # (1 of 2) find with proper opts
  def find(opts) when is_list(opts) and opts != [] do
    case Repo.get_by(Schema, opts) do
      %Schema{} = x -> load_device(x)
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

  def names do
    Query.from(x in Schema, select: x.name, order_by: x.name) |> Repo.all()
  end

  def names_begin_with(pattern) when is_binary(pattern) do
    like_string = [pattern, "%"] |> IO.iodata_to_binary()

    Query.from(x in Schema, where: like(x.name, ^like_string), order_by: x.name, select: x.name) |> Repo.all()
  end

  def rename(%Schema{} = a, changes) when is_map(changes) do
    case changeset(a, changes) |> Repo.update(returning: true) do
      {:ok, %Schema{} = revised} -> {:ok, [name: revised.name, was: a.name]}
      error -> error
    end
  end

  # @doc """
  # Replace a Sensor by assigning the existing Alias to a different Device.
  # """
  # @doc since: "0.0.27"
  # def replace(name_or_id, dev_name_or_id) do
  #   with {:alias, %Schema{} = a} <- {:alias, find(name_or_id)},
  #        {:dev, %Device{id: dev_id}} <- {:dev, Device.find(dev_name_or_id)},
  #        {:ok, %Schema{}} <- update(a, [device_id: dev_id], []) do
  #     {:ok, dev_name_or_id}
  #   else
  #     {:alias, rc} -> {:alias_error, rc}
  #     {:dev, rc} -> {:device_error, rc}
  #     rc -> rc
  #   end
  # end

  def upsert(p) when is_map(p) do
    changes = Map.take(p, columns(:all))
    cs = changeset(%Schema{}, changes)

    opts = [on_conflict: {:replace, columns(:replace)}, returning: true, conflict_target: [:name]]

    case Repo.insert(cs, opts) do
      {:ok, %Schema{}} = rc -> rc
      {:error, e} -> {:error, inspect(e, pretty: true)}
    end
  end

  defp load_datapoint_ids(schema_or_nil) do
    q = Query.from(dp in DataPoint, select: [:id])
    Repo.preload(schema_or_nil, [datapoints: q], force: true)
  end

  defp load_device(%Schema{} = a), do: Repo.preload(a, [:device])

  # defp mark_as_updated(%Schema{} = a) do
  #   a
  #   |> changeset(%{updated_at: DateTime.utc_now()})
  #   |> Repo.update(returning: true)
  # end
end
