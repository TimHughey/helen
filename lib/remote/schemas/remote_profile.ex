defmodule RemoteProfile.Schema do
  @moduledoc """
    Schema definition for Remote Profiles (configuration)
  """

  require Logger
  use Timex
  use Ecto.Schema

  import Common.DB, only: [name_regex: 0]

  alias RemoteProfile.Schema

  schema "remote_profile" do
    field(:name, :string)
    field(:version, Ecto.UUID, autogenerate: true)

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
    field(:dalsemi_core_interval_secs, :integer, default: 30)
    field(:dalsemi_discover_interval_secs, :integer, default: 30)
    field(:dalsemi_convert_interval_secs, :integer, default: 7)
    field(:dalsemi_report_interval_secs, :integer, default: 7)

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
    field(:i2c_core_interval_secs, :integer, default: 7)
    field(:i2c_discover_interval_secs, :integer, default: 60)
    field(:i2c_report_interval_secs, :integer, default: 7)

    field(:pwm_enable, :boolean, default: true)
    field(:pwm_core_stack, :integer, default: 1536)
    field(:pwm_core_priority, :integer, default: 1)
    field(:pwm_discover_stack, :integer, default: 2048)
    field(:pwm_discover_priority, :integer, default: 12)
    field(:pwm_report_stack, :integer, default: 2048)
    field(:pwm_report_priority, :integer, default: 12)
    field(:pwm_command_stack, :integer, default: 2048)
    field(:pwm_command_priority, :integer, default: 14)
    field(:pwm_core_interval_secs, :integer, default: 10)
    field(:pwm_report_interval_secs, :integer, default: 10)

    field(:timestamp_task_stack, :integer, default: 1536)
    field(:timestamp_task_priority, :integer, default: 0)
    field(:timestamp_watch_stacks, :boolean, default: false)
    field(:timestamp_core_interval_secs, :integer, default: 3)
    field(:timestamp_report_interval_secs, :integer, default: 3600)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
    Creates a new Remote Profile with specified name and optional parameters

      ## Examples
        iex> RemoteProfile.Schema.create("default", dalsemi_enable: true,
            i2c_enable: true, pwm_enable: false)
            %RemoteProfile.Schema{}
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
    Get a %RemoteProfile.Schema{} by id or name

    Same return values as Repo.get_by/2

      1. nil if not found
      2. %RemoteProfile.Schema{}

      ## Examples
        iex> RemoteProfile.Schema.find("default")
        {:ok, %RemoteProfile.Schema{}}
  """

  @doc since: "0.0.8"
  def find(id) when is_integer(id),
    do: Repo.get_by(__MODULE__, id: id)

  def find(name) when is_binary(name),
    do: Repo.get_by(__MODULE__, name: name)

  def find(bad_args), do: {:bad_args, bad_args}

  @doc """
    Reload a previously loaded RemoteProfile.Schema or get by id

    Leverages Repo.get!/2 and raises on failure

    ## Examples
      iex> RemoteProfile.Schema.reload(1)
      %RemoteProfile.Schema{}
  """

  @doc since: "0.0.8"
  def reload({:ok, %Schema{id: id}}), do: reload(id)

  def reload(%Schema{id: id}), do: reload(id)

  def reload(id) when is_number(id), do: Repo.get!(__MODULE__, id)

  def reload(catchall), do: {:error, catchall}

  @doc """
    Converts a Remote Profile to a map that can be used externally.

      ## Examples
        iex> RemoteProfile.Schema.to_external_map("default")
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
    p = find(name)

    %{
      meta: %{
        profile: p.name,
        version: p.version,
        updated_mtime: Timex.to_unix(p.updated_at),
        inserted_mtime: Timex.to_unix(p.inserted_at)
      },
      ds: %{
        enable: p.dalsemi_enable,
        core: %{
          stack: p.dalsemi_core_stack,
          pri: p.dalsemi_core_priority,
          interval_secs: p.dalsemi_core_interval_secs
        },
        discover: %{
          stack: p.dalsemi_discover_stack,
          pri: p.dalsemi_discover_priority,
          interval_secs: p.dalsemi_discover_interval_secs
        },
        report: %{
          stack: p.dalsemi_report_stack,
          pri: p.dalsemi_report_priority,
          interval_secs: p.dalsemi_report_interval_secs
        },
        convert: %{
          stack: p.dalsemi_convert_stack,
          pri: p.dalsemi_convert_priority,
          interval_secs: p.dalsemi_convert_interval_secs
        },
        command: %{
          stack: p.dalsemi_command_stack,
          pri: p.dalsemi_command_priority
        },
        i2c: %{
          enable: p.i2c_enable,
          core: %{
            stack: p.i2c_core_stack,
            pri: p.i2c_core_priority,
            interval_secs: p.i2c_core_interval_secs
          },
          discover: %{
            stack: p.i2c_discover_stack,
            pri: p.i2c_discover_priority,
            interval_secs: p.i2c_discover_interval_secs
          },
          report: %{
            stack: p.i2c_report_stack,
            pri: p.i2c_report_priority,
            interval_secs: p.i2c_report_interval_secs
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
            interval_secs: p.pwm_core_interval_secs
          },
          discover: %{
            stack: p.pwm_discover_stack,
            pri: p.pwm_discover_priority
          },
          report: %{
            stack: p.pwm_report_stack,
            pri: p.pwm_report_priority,
            interval_secs: p.pwm_report_interval_secs
          },
          command: %{
            stack: p.pwm_command_stack,
            pri: p.pwm_command_priority
          }
        },
        timestamp: %{
          stack: p.timestamp_task_stack,
          pri: p.timestamp_task_priority,
          watch_stacks: p.timestamp_watch_stacks,
          core_interval_secs: p.timestamp_core_interval_secs,
          report_interval_secs: p.timestamp_report_interval_secs
        }
      }
    }
  end

  @doc """
    Updates an existing Remote Profile using the provided list of opts

    >
    > `:version` is updated if any changes to other data are performed.
    >

      ## Examples
        iex> RemoteProfile.Schema.update("default", [i2c_enable: false])
  """

  @doc since: "0.0.8"
  def update(%Schema{id: id} = x, opts) when is_integer(id) and is_list(opts) do
    import Ecto.Changeset, only: [cast: 3]

    with {:bad_opts, []} <- {:bad_opts, Keyword.drop(opts, keys(:all))},
         cs <- changeset(x, opts),
         {:cs_valid, cs, true} <- {:cs_valid, cs, cs.valid?},
         {:changes, true} <- {:changes, map_size(cs.changes) > 0},
         cs <- cast(x, %{version: Ecto.UUID.generate()}, [:version]),
         {:cs_valid, cs, true} <- {:cs_valid, cs, cs.valid?} do
      Repo.update(cs)
    else
      {:bad_opts, u} -> {:unrecognized_opts, u}
      {:changes, false} -> {:no_changes, x}
      {:cs_valid, cs, false} -> {:invalid_changes, cs}
      error -> {:error, error}
    end
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

  defp keys(:create_opts) do
    Map.from_struct(%Schema{})
    |> Map.drop([:name, :version, :inserted_at, :updated_at])
    |> Map.keys()
  end

  defp keys(:all),
    do:
      [keys_base(), keys_dalsemi(), keys_i2c(), keys_pwm(), keys_timestamp()]
      |> List.flatten()

  defp keys_base, do: [:name, :version]

  defp keys_dalsemi,
    do: [
      :dalsemi_enable,
      :dalsemi_core_stack,
      :dalsemi_core_priority,
      :dalsemi_discover_stack,
      :dalsemi_discover_priority,
      :dalsemi_report_stack,
      :dalsemi_report_priority,
      :dalsemi_convert_stack,
      :dalsemi_convert_priority,
      :dalsemi_command_stack,
      :dalsemi_command_priority,
      :dalsemi_core_interval_secs,
      :dalsemi_discover_interval_secs,
      :dalsemi_convert_interval_secs,
      :dalsemi_report_interval_secs
    ]

  defp keys_i2c,
    do: [
      :i2c_enable,
      :i2c_use_multiplexer,
      :i2c_core_stack,
      :i2c_core_priority,
      :i2c_discover_stack,
      :i2c_discover_priority,
      :i2c_report_stack,
      :i2c_report_priority,
      :i2c_command_stack,
      :i2c_command_priority,
      :i2c_core_interval_secs,
      :i2c_discover_interval_secs,
      :i2c_report_interval_secs
    ]

  defp keys_pwm,
    do: [
      :pwm_enable,
      :pwm_core_stack,
      :pwm_core_priority,
      :pwm_discover_stack,
      :pwm_discover_priority,
      :pwm_report_stack,
      :pwm_report_priority,
      :pwm_command_stack,
      :pwm_command_priority,
      :pwm_core_interval_secs,
      :pwm_report_interval_secs
    ]

  defp keys_timestamp,
    do: [
      :timestamp_task_stack,
      :timestamp_task_priority,
      :timestamp_watch_stacks,
      :timestamp_core_interval_secs,
      :timestamp_report_interval_secs
    ]
end
