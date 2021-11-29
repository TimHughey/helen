defmodule Sally.Repo.Migrations.Initial do
  use Ecto.Migration

  def change do
    create_host()
    create_device()
    create_dev_alias()
    create_datapoint()
    create_command()
  end

  defp create_command do
    create table(:command) do
      add(:dev_alias_id, references(:dev_alias, on_delete: :delete_all, on_update: :update_all))
      add(:cmd, :string, size: 32, null: false)
      add(:refid, :string, size: 8, null: false)
      add(:acked, :boolean, null: false, default: false)
      add(:orphaned, :boolean, null: false, default: false)
      add(:sent_at, :utc_datetime_usec, null: false)
      add(:acked_at, :utc_datetime_usec)
      add(:rt_latency_us, :integer, default: 0)
    end

    create(index(:command, [:refid], unique: true))
    create(index(:command, [:sent_at], using: :brin))
  end

  defp create_datapoint do
    create table(:datapoint) do
      add(:dev_alias_id, references(:dev_alias, on_delete: :delete_all, on_update: :update_all))
      add(:temp_c, :float)
      add(:relhum, :float)
      add(:reading_at, :utc_datetime_usec)
    end

    create(index(:datapoint, [:reading_at], using: :brin))
  end

  defp create_device do
    create table(:device) do
      add(:host_id, references(:host, on_delete: :delete_all, on_update: :update_all))
      add(:ident, :string, size: 128, null: false)
      add(:family, :string, size: 24, null: false)
      add(:mutable, :boolean, null: false)
      add(:pios, :integer, null: false)
      add(:last_seen_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:device, [:ident], unique: true))
  end

  def create_dev_alias do
    create table(:dev_alias) do
      add(:device_id, references(:device, on_delete: :delete_all, on_update: :update_all))
      add(:name, :string, size: 128, null: false)
      add(:pio, :integer, null: false)
      add(:description, :string, size: 128)
      add(:ttl_ms, :integer, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:dev_alias, [:name], unique: true))
  end

  defp create_host do
    create table(:host) do
      add(:ident, :string, size: 24, null: false)
      add(:name, :string, size: 32, null: false)
      add(:profile, :string, size: 32, null: false)
      add(:authorized, :boolean, null: false)
      add(:firmware_vsn, :string, size: 32)
      add(:idf_vsn, :string, size: 12)
      add(:app_sha, :string, size: 12)
      add(:reset_reason, :string, size: 24)
      add(:build_at, :utc_datetime_usec)
      add(:last_start_at, :utc_datetime_usec, null: false)
      add(:last_seen_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:host, [:ident], unique: true))
    create(index(:host, [:name], unique: true))
  end
end
