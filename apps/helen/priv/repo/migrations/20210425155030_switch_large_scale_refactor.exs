defmodule Repo.Migrations.SwitchLargeScaleRefactor do
  use Ecto.Migration

  def change do
    switch_cmd()
    switch_device()
  end

  def switch_cmd do
    # drop indexes
    for index <- [:alias_id, :acked, :orphan, :refid] do
      drop_if_exists(index(:switch_command, [index]))
    end

    # Drop the existing forgeign key and primary key constraints by their
    # default names from when they were generated automatically by Ecto.
    drop(constraint(:switch_command, "switch_command_alias_id_fkey"))
    drop(constraint(:switch_command, "switch_command_device_id_fkey"))
    drop(constraint(:switch_command, "switch_command_pkey"))

    # Rename the table
    rename(table(:switch_command), to: table(:switch_cmd))

    alter table(:switch_cmd) do
      remove_if_exists(:device_id, :bigint)
      # "Modifying" the columns rengenerates the constraints with the correct
      # new names. These were the same types and options the columns were
      # originally created with in previous migrations.
      modify(:id, :bigint, primary_key: true)
      modify(:alias_id, references(:switch_alias))
    end

    # Rename the ID sequence. I don't think this affects Ecto, but it keeps
    # the naming and structure of the table more consistent.
    execute("ALTER SEQUENCE switch_command_id_seq RENAME TO switch_cmd_id_seq;")

    create(index(:switch_cmd, [:alias_id]))
    create(index(:switch_cmd, [:acked]))
    create(index(:switch_cmd, [:refid], unique: true))
    create(index(:switch_cmd, [:sent_at], using: :brin))
  end

  def switch_device do
    alter table(:switch_device) do
      remove_if_exists(:states, :map)
      remove_if_exists(:ttl_ms, :integer)
      remove_if_exists(:last_cmd_at, :utc_datetime_usec)
    end

    create(index(:switch_device, [:id]))
  end
end
