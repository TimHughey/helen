defmodule Repo.Migrations.ReviseRemote do
  use Ecto.Migration

  def change do
    alter table("remote") do
      # removing(unused(columns))

      remove(:preferred_vsn, :string, default: "stable")
      remove(:hw, :string, null: false)
      remove(:project_name, :string)
      remove(:magic_word, :string)
      remove(:secure_vsn, :string)
      remove(:ap_sec_chan, :integer)
      remove(:metric_at, :utc_datetime_usec, default: nil)
      remove(:metric_freq_secs, :integer, default: 60)

      remove(:runtime_metrics, :map,
        null: false,
        default: %{external_update: false, cmd_rt: true}
      )
    end
  end
end
