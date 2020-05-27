defmodule Repo.Migrations.RemoveUnusedPulseWidthColumns do
  use Ecto.Migration

  def change do
    alter table("pwm") do
      # removing metric frequency functionality until a better
      # approach is decided
      remove(:metric_freq_secs, :integer, default: 60)
      remove(:metric_at, :utc_datetime_usec, default: nil)

      remove(:runtime_metrics, :map,
        null: false,
        default: %{external_update: false, cmd_rt: true}
      )
    end
  end
end
