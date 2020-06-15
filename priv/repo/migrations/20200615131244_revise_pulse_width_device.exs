defmodule Repo.Migrations.RevisePulseWidthDevice do
  use Ecto.Migration

  def change do
    drop = [:name, :device, :host, :last_cmd_at, :last_seen_at]

    for d <- drop, do: drop_if_exists(index("pwm", [d]))

    alter table("pwm_device") do
      # removing unnecessary columns and/or  moved to PulseWidth.DB.Alias

      remove(:name, :string)
      remove(:description, :string)
      remove(:running_cmd, :string, default: "none")
      remove(:log, :boolean, default: false)
      remove(:ttl_ms, :integer, default: 60_000)
      remove(:reading_at, :utc_datetime_usec)
    end

    create(
      index("pwm_device", [:device],
        name: "pwm_device_unique_index",
        unique: true
      )
    )
  end
end
