defmodule Remote.DB.Profile do
  @moduledoc """
  Database implementation for Remote Profile
  """

  use Ecto.Schema

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

  alias Remote.DB.Profile, as: Schema

  @doc """
    Converts a Remote Profile to a map that can be used externally.

      ## Examples
        iex> Remote.DB.Profile.as_external_map("default")
        %{
         meta: %{version: "", updated_mtime: 12345, inserted_mtime: 12345},
         ds: %{enable: true,
          core: %{stack: 2048, pri: 0},
          convert: %{stack: 2048, pri: 14},
          ...
        }
  """

  @doc since: "0.0.8"
  def as_external_map(%Schema{} = p) do
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

    import Common.DB, only: [name_regex: 0]

    x
    |> cast(params, keys(:all))
    |> validate_format(:name, name_regex())
    |> unique_constraint(:name, [:name])
  end

  @doc """
    Creates a new Remote Profile with specified name and optional parameters

      ## Examples
        iex> Remote.DB.Profile.create("default", dalsemi_enable: true,
            i2c_enable: true, pwm_enable: false)
            {:ok, }%Remote.DB.Profile{}}

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
    Create the command payload for a Profile

  """
  @doc since: "0.0.21"
  def create_profile_payload(%{host: host, name: name}, %Schema{} = p) do
    import Helen.Time.Helper, only: [unix_now: 1]

    Map.merge(
      %{
        payload: "profile",
        mtime: unix_now(:second),
        host: host,
        assigned_name: name
      },
      as_external_map(p)
    )
  end

  def keys(:all),
    do:
      %Schema{}
      |> Map.from_struct()
      |> Map.drop([:__meta__])
      |> Map.keys()
      |> List.flatten()

  def keys(:create_opts),
    do:
      keys(:update_opts)
      |> List.delete(:name)

  def keys(:update_opts) do
    all = keys(:all) |> MapSet.new()
    remove = MapSet.new([:id, :version, :inserted_at, :updated_at])
    MapSet.difference(all, remove) |> MapSet.to_list()
  end

  @doc """
    Duplicate an existing Remote Profile

    Ultimately calls create/2 so same return results

      ## Examples
        iex> Remote.DB.Profile.duplicate(name, copy_name)
        {:ok, %Remote.DB.Profile{}}

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
    Get a %Remote.DB.Profile{} by id or name

    Same return values as Repo.get_by/2

      1. nil if not found
      2. %Remote.DB.Profile{}

      ## Examples
        iex> Remote.DB.Profile.find("default")
        %Remote.DB.Profile{}
  """

  @doc since: "0.0.8"
  def find(id_or_name) when is_integer(id_or_name) or is_binary(id_or_name) do
    check_args = fn
      x when is_binary(x) -> [name: x]
      x when is_integer(x) -> [id: x]
      x -> {:bad_args, x}
    end

    import Repo, only: [get_by: 2, preload: 2]

    with opts when is_list(opts) <- check_args.(id_or_name),
         %Schema{} = found <- get_by(Schema, opts) do
      found
    else
      x when is_tuple(x) -> x
      x when is_nil(x) -> nil
      x -> {:error, x}
    end
  end

  def lookup_key(key) do
    keys(:all)
    |> Enum.filter(fn x ->
      str = Atom.to_string(x)
      String.contains?(str, key)
    end)
  end

  @doc """
    Reload a previously loaded Remote.DB.Profile or get by id

    Leverages Repo.get!/2 and raises on failure

    ## Examples
      iex> Remote.DB.Profile.reload(1)
      %Remote.DB.Profile{}
  """

  @doc since: "0.0.8"
  def reload(opt) do
    handle_args = fn
      {:ok, %Schema{id: id}} -> id
      %Schema{id: id} -> id
      id when is_integer(id) -> id
      x -> x
    end

    import Repo, only: [get!: 2]

    case handle_args.(opt) do
      id when is_integer(id) -> get!(Schema, id)
      x -> {:error, x}
    end
  end

  @doc """
    Retrieve Remote Profile Names

    ## Examples
      iex> Remote.DB.Profile.names()
      ["default"]
  """

  @doc since: "0.0.8"
  def names do
    import Ecto.Query, only: [from: 2]

    from(x in Schema, select: x.name, order_by: [:name]) |> Repo.all()
  end

  @doc """
  Lookup a Profile and convert to for external use
  """

  @doc since: "0.0.20"
  def to_external_map(name) do
    case find(name) do
      %Schema{} = p -> as_external_map(p)
      _not_found -> &{}
    end
  end

  @doc """
    Updates an existing Remote Profile using the provided list of opts

    >
    > `:version` is updated when changeset contains changes.
    >

      ## Examples

        Update by profile name

        iex> Remote.DB.Profile.update("default", [i2c_enable: false])
        {:ok, %Remote.DB.Profile{}}

        Update by profile id

        iex> Remote.DB.Profile.update(12, [i2c_enable: false])
        {:ok, %Remote.DB.Profile{}}

        Update in a pipeline (e.g. Remote.DB.Profile.duplicate/2)

        iex> Remote.DB.Profile.update({:ok, %Remote.DB.Profile{}}, opts)
        {:ok, %Remote.DB.Profile{}}
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
    with {:ok, %Schema{name: name} = p} <- find(id_or_name) |> update(opts),
         res <- Map.take(p, Keyword.keys(opts)) |> Enum.to_list() do
      [name: name] ++ res
    else
      error -> error
    end
  end

  def update(catchall) do
    {:error, catchall}
  end
end
