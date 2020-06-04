defmodule Remote.Schemas.Profile do
  @moduledoc """
    Schema definition for Remote Profiles (configuration)
  """

  use Ecto.Schema

  alias Remote.Schemas.Profile, as: Schema

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
    Create the command payload for a Profile

  """
  @doc since: "0.0.21"
  def create_profile_payload(%{host: host, name: name}, %Schema{} = p) do
    Map.merge(
      %{
        payload: "profile",
        mtime: TimeSupport.unix_now(:second),
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
    Converts a Remote Profile to a map that can be used externally.

      ## Examples
        iex> Remote.Schemas.Profile.as_external_map("default")
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
end
