defmodule Remote.Profile.Schema do
  @moduledoc """
    Schema definition for Remote Profiles (configuration)
  """

  require Logger
  use Timex
  use Ecto.Schema

  import Common.DB, only: [name_regex: 0]

  alias Remote.Profile.Schema

  schema "remote_profile" do
    field(:name, :string)
    field(:description, :string)
    field(:version, Ecto.UUID, autogenerate: true)
    field(:watch_stacks, :boolean, default: false)
    field(:core_loop_interval_ms, :integer, default: 1000)
    field(:core_timestamp_ms, :integer, default: 6 * 60 * 1000)

    field(:dalsemi_enable, :boolean, default: true)
    field(:dalsemi_core_stack, :integer, default: 1536)
    field(:dalsemi_core_priority, :integer, default: 1)
    field(:dalsemi_discover_stack, :integer, default: 4096)
    field(:dalsemi_discover_priority, :integer, default: 12)
    field(:dalsemi_report_stack, :integer, default: 3072)
    field(:dalsemi_report_priority, :integer, default: 13)
    field(:dalsemi_convert_stack, :integer, default: 2048)
    field(:dalsemi_convert_priority, :integer, default: 13)
    field(:dalsemi_command_stack, :integer, default: 3072)
    field(:dalsemi_command_priority, :integer, default: 14)
    field(:dalsemi_core_interval_ms, :integer, default: 30)
    field(:dalsemi_discover_interval_ms, :integer, default: 30)
    field(:dalsemi_convert_interval_ms, :integer, default: 7)
    field(:dalsemi_report_interval_ms, :integer, default: 7)

    field(:i2c_enable, :boolean, default: true)
    field(:i2c_use_multiplexer, :boolean, default: false)
    field(:i2c_core_stack, :integer, default: 1536)
    field(:i2c_core_priority, :integer, default: 1)
    field(:i2c_discover_stack, :integer, default: 4096)
    field(:i2c_discover_priority, :integer, default: 12)
    field(:i2c_report_stack, :integer, default: 3072)
    field(:i2c_report_priority, :integer, default: 13)
    field(:i2c_command_stack, :integer, default: 3072)
    field(:i2c_command_priority, :integer, default: 14)
    field(:i2c_core_interval_ms, :integer, default: 7)
    field(:i2c_discover_interval_ms, :integer, default: 60)
    field(:i2c_report_interval_ms, :integer, default: 7)

    field(:pwm_enable, :boolean, default: true)
    field(:pwm_core_stack, :integer, default: 1536)
    field(:pwm_core_priority, :integer, default: 1)
    field(:pwm_report_stack, :integer, default: 2048)
    field(:pwm_report_priority, :integer, default: 12)
    field(:pwm_command_stack, :integer, default: 2048)
    field(:pwm_command_priority, :integer, default: 14)
    field(:pwm_core_interval_ms, :integer, default: 10)
    field(:pwm_report_interval_ms, :integer, default: 10)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
    Creates a new Remote Profile with specified name and optional parameters

      ## Examples
        iex> Remote.Profile.Schema.create("default", dalsemi_enable: true,
            i2c_enable: true, pwm_enable: false)
            {:ok, }%Remote.Profile.Schema{}}

            {:duplicate, name}

            {:error, anything}
  """
  @doc since: "0.0.8"
  def create(name, opts \\ []) when is_binary(name) and is_list(opts) do
    params =
      Keyword.take(opts, keys(:create_opts))
      |> Enum.into(%{})
      |> Map.merge(%{name: name})

    cs = changeset(%Schema{}, params)

    with {:cs_valid, true} <- {:cs_valid, cs.valid?()},
         {:ok, %Schema{id: id} = x} <-
           Repo.insert(cs,
             on_conflict: :nothing,
             returning: true,
             conflict_target: [:name]
           ),
         {:id_valid, true} <- {:id_valid, is_integer(id)} do
      {:ok, x}
    else
      {:id_valid, false} -> {:duplicate, name}
      catchall -> {:error, catchall}
    end
  end

  @doc """
    Duplicate an existing Remote Profile

    Ultimately calls create/2 so same return results

      ## Examples
        iex> Remote.Profile.Schema.duplicate(name, copy_name)
        {:ok, %Remote.Profile.Schema{}}

        {:not_found, name}
  """

  @doc since: "0.0.8"
  def duplicate(name, copy_name)
      when is_binary(name) and is_binary(copy_name) do
    with {:find, %Schema{} = x} <- {:find, find(name)},
         source_map <- Map.from_struct(x) |> Map.take(keys(:create_opts)),
         description <- ["copy of", name] |> Enum.join(" "),
         source_map <- Map.put(source_map, :description, description),
         copy_opts <- Map.to_list(source_map) do
      create(copy_name, copy_opts)
    else
      {:find, nil} -> {:not_found, name}
      error -> {:error, error}
    end
  end

  @doc """
    Get a %Remote.Profile.Schema{} by id or name

    Same return values as Repo.get_by/2

      1. nil if not found
      2. %Remote.Profile.Schema{}

      ## Examples
        iex> Remote.Profile.Schema.find("default")
        %Remote.Profile.Schema{}
  """

  @doc since: "0.0.8"
  def find(id) when is_integer(id),
    do: Repo.get_by(__MODULE__, id: id)

  def find(name) when is_binary(name),
    do: Repo.get_by(__MODULE__, name: name)

  def find(bad_args), do: {:bad_args, bad_args}

  @doc """
    Reload a previously loaded Remote.Profile.Schema or get by id

    Leverages Repo.get!/2 and raises on failure

    ## Examples
      iex> Remote.Profile.Schema.reload(1)
      %Remote.Profile.Schema{}
  """

  @doc since: "0.0.8"
  def reload({:ok, %Schema{id: id}}), do: reload(id)

  def reload(%Schema{id: id}), do: reload(id)

  def reload(id) when is_number(id), do: Repo.get!(__MODULE__, id)

  def reload(catchall), do: {:error, catchall}

  @doc """
    Retrieve Remote Profile Names

    ## Examples
      iex> Remote.Profile.Schema.names()
      ["default"]
  """

  @doc since: "0.0.8"
  def names do
    import Ecto.Query, only: [from: 2]

    from(x in Schema, select: x.name) |> Repo.all()
  end

  @doc """
    Converts a Remote Profile to a map that can be used externally.

      ## Examples
        iex> Remote.Profile.Schema.to_external_map("default")
        %{
         meta: %{version: "", updated_mtime: 12345, inserted_mtime: 12345},
         ds: %{enable: true,
          core: %{stack: 2048, pri: 0},
          convert: %{stack: 2048, pri: 14},
          ...
        }
  """

  @doc since: "0.0.8"
  def to_external_map(name) do
    with %Schema{} = p <- find(name) do
      %{
        meta: %{
          profile: p.name,
          version: p.version
        },
        core: %{
          loop_ms: p.core_loop_interval_ms,
          timestamp_ms: p.core_timestamp_ms
        },
        ds: %{
          enable: p.dalsemi_enable,
          core: %{
            stack: p.dalsemi_core_stack,
            pri: p.dalsemi_core_priority,
            interval_ms: p.dalsemi_core_interval_ms
          },
          discover: %{
            stack: p.dalsemi_discover_stack,
            pri: p.dalsemi_discover_priority,
            interval_ms: p.dalsemi_discover_interval_ms
          },
          report: %{
            stack: p.dalsemi_report_stack,
            pri: p.dalsemi_report_priority,
            interval_ms: p.dalsemi_report_interval_ms
          },
          convert: %{
            stack: p.dalsemi_convert_stack,
            pri: p.dalsemi_convert_priority,
            interval_ms: p.dalsemi_convert_interval_ms
          },
          command: %{
            stack: p.dalsemi_command_stack,
            pri: p.dalsemi_command_priority
          }
        },
        i2c: %{
          enable: p.i2c_enable,
          core: %{
            stack: p.i2c_core_stack,
            pri: p.i2c_core_priority,
            interval_ms: p.i2c_core_interval_ms
          },
          discover: %{
            stack: p.i2c_discover_stack,
            pri: p.i2c_discover_priority,
            interval_ms: p.i2c_discover_interval_ms
          },
          report: %{
            stack: p.i2c_report_stack,
            pri: p.i2c_report_priority,
            interval_ms: p.i2c_report_interval_ms
          },
          command: %{
            stack: p.i2c_command_stack,
            pri: p.i2c_command_priority
          }
        },
        pwm: %{
          enable: p.pwm_enable,
          core: %{
            stack: p.pwm_core_stack,
            pri: p.pwm_core_priority,
            interval_ms: p.pwm_core_interval_ms
          },
          report: %{
            stack: p.pwm_report_stack,
            pri: p.pwm_report_priority,
            interval_ms: p.pwm_report_interval_ms
          },
          command: %{
            stack: p.pwm_command_stack,
            pri: p.pwm_command_priority
          }
        },
        misc: %{
          watch_stacks: p.watch_stacks,
          i2c_mplex: p.i2c_use_multiplexer
        }
      }
    else
      _not_found -> %{}
    end
  end

  @doc """
    Updates an existing Remote Profile using the provided list of opts

    >
    > `:version` is updated when changeset contains changes.
    >

      ## Examples

        Update by profile name

        iex> Remote.Profile.Schema.update("default", [i2c_enable: false])
        {:ok, %Remote.Profile.Schema{}}

        Update by profile id

        iex> Remote.Profile.Schema.update(12, [i2c_enable: false])
        {:ok, %Remote.Profile.Schema{}}

        Update in a pipeline (e.g. Remote.Profile.Schema.duplicate/2)

        iex> Remote.Profile.Schema.update({:ok, %Remote.Profile.Schema{}}, opts)
        {:ok, %Remote.Profile.Schema{}}
  """

  @doc since: "0.0.8"
  def update(%Schema{id: id} = x, opts) when is_integer(id) and is_list(opts) do
    import Ecto.Changeset, only: [cast: 3]

    with {:bad_opts, []} <- {:bad_opts, Keyword.drop(opts, keys(:all))},
         cs <- changeset(x, opts),
         {:cs_valid, cs, true} <- {:cs_valid, cs, cs.valid?},
         {:changes, true} <- {:changes, map_size(cs.changes) > 0},
         cs <- cast(cs, %{version: Ecto.UUID.generate()}, [:version]),
         {:cs_valid, cs, true} <- {:cs_valid, cs, cs.valid?} do
      Repo.update(cs, returning: true)
    else
      {:bad_opts, u} -> {:unrecognized_opts, u}
      {:changes, false} -> {:no_changes, x}
      {:cs_valid, cs, false} -> {:invalid_changes, cs}
      error -> {:error, error}
    end
  end

  def update({:ok, %Schema{id: _} = x}, opts) when is_list(opts) do
    update(x, opts)
  end

  def update({rc, error}, _opts) do
    {rc, error}
  end

  def update(id_or_name, opts)
      when is_integer(id_or_name) or is_binary(id_or_name) do
    find(id_or_name) |> update(opts)
  end

  def update(catchall) do
    Logger.warn(["update/2 error: ", inspect(catchall, pretty: true)])
    {:error, catchall}
  end

  def changeset(x, params) when is_list(params) do
    changeset(x, Enum.into(params, %{}))
  end

  def changeset(x, params) when is_map(params) do
    import Ecto.Changeset,
      only: [
        cast: 3,
        unique_constraint: 3,
        validate_format: 3
      ]

    x
    |> cast(params, keys(:all))
    |> validate_format(:name, name_regex())
    |> unique_constraint(:name, [:name])
  end

  defp keys(:all),
    do:
      %Schema{}
      |> Map.from_struct()
      |> Map.drop([:__meta__])
      |> Map.keys()
      |> List.flatten()

  defp keys(:create_opts),
    do:
      keys(:update_opts)
      |> List.delete(:name)

  defp keys(:update_opts) do
    all = keys(:all) |> MapSet.new()
    remove = MapSet.new([:id, :version, :inserted_at, :updated_at])
    MapSet.difference(all, remove) |> MapSet.to_list()
  end
end
