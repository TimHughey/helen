defmodule SallyRepo.Migrations.CreatePulseWidthSchemas do
  use Ecto.Migration

  def change do
    create table(:pwm_device) do
      add(:ident, :string, size: 128, null: false)
      add(:host, :string, size: 128, null: false)
      add(:pios, :integer, null: false)
      add(:latency_us, :integer, default: 0)
      add(:last_seen_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:pwm_device, [:ident], name: "pwm_device_ident_index", unique: true))

    create table(:pwm_alias) do
      add(:name, :string, size: 128, null: false)
      add(:device_id, references(:pwm_device, on_delete: :delete_all, on_update: :update_all))
      add(:description, :string, size: 50, default: "<none>")
      add(:cmd, :string, size: 32, null: false, default: "unknown")
      add(:pio, :integer, null: false)
      add(:ttl_ms, :integer, null: false, default: 60_000)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:pwm_alias, [:name], name: "pwm_alias_name_index", unique: true))

    create table(:pwm_cmd) do
      add(:cmd, :string, size: 32, null: false, default: "unknown")
      add(:alias_id, references(:pwm_alias, on_delete: :delete_all, on_update: :update_all))
      add(:refid, :string, size: 8, null: false)
      add(:acked, :boolean, null: false, default: false)
      add(:orphaned, :boolean, null: false, default: false)
      add(:sent_at, :utc_datetime_usec, null: false)
      add(:acked_at, :utc_datetime_usec)
      add(:rt_latency_us, :integer, default: 0)
    end

    create(index(:pwm_cmd, [:refid], name: "pwm_cmd_refid_index", unique: true))
    create(index(:pwm_cmd, [:sent_at], name: "pwm_cmd_sent_at_index", using: :brin))
  end
end
