defmodule Repo.Migrations.ChangePulseWidthCmdTimestampsToMicrosecondPrecision do
  use Ecto.Migration

  def change do
    current_time = fragment(~s/(now() at time zone 'utc')/)

    drop_if_exists(index(:pwm_cmd, [:acked]))
    drop_if_exists(index(:pwm_cmd, [:refid]))
    drop_if_exists(table(:pwm_cmd))

    create_if_not_exists table(:pwm_cmd) do
      add(
        :pwm_id,
        references(:pwm, on_delete: :delete_all, on_update: :update_all)
      )

      add(:refid, :uuid)
      add(:acked, :boolean, null: false, default: false)
      add(:orphan, :boolean, null: false, default: false)
      add(:rt_latency_us, :integer, null: false, default: 0)
      add(:sent_at, :utc_datetime_usec, null: false, default: current_time)
      add(:ack_at, :utc_datetime_usec, null: true, default: nil)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(:pwm_cmd, [:acked]))
    create_if_not_exists(index(:pwm_cmd, [:refid], unique: true))
  end
end
