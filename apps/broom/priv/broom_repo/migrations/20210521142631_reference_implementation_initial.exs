defmodule BroomRepo.Migrations.ReferenceImplementationInitial do
  use Ecto.Migration

  def change do
    create table(:broom_device) do
      add(:ident, :string, size: 128, null: false)
      add(:host, :string, size: 128, null: false)
      add(:pios, :integer, null: false)
      add(:latency_us, :integer, default: 0)
      add(:last_seen_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:broom_device, [:ident], name: "broom_device_ident_index", unique: true))

    create table(:broom_alias) do
      add(:name, :string, size: 128, null: false)
      add(:device_id, references(:broom_device, on_delete: :delete_all, on_update: :update_all))
      add(:description, :string, size: 50, default: "<none>")
      add(:cmd, :string, size: 32, null: false, default: "unknown")
      add(:pio, :integer, null: false)
      add(:ttl_ms, :integer, null: false, default: 60_000)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:broom_alias, [:name], name: "broom_alias_name_index", unique: true))

    create table(:broom_cmd) do
      add(:cmd, :string, size: 32, null: false, default: "unknown")
      add(:alias_id, references(:broom_alias, on_delete: :delete_all, on_update: :update_all))
      add(:refid, :string, size: 8, null: false)
      add(:acked, :boolean, null: false, default: false)
      add(:orphaned, :boolean, null: false, default: false)
      add(:sent_at, :utc_datetime_usec, null: false)
      add(:acked_at, :utc_datetime_usec)
      add(:rt_latency_us, :integer, default: 0)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:broom_cmd, [:refid], name: "broom_cmd_refid_index", unique: true))
  end
end
