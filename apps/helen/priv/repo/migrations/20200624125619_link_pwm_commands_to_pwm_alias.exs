defmodule Repo.Migrations.LinkPwmCommandsToPwmAlias do
  use Ecto.Migration

  def change do
    alter table("pwm_cmd") do
      add(:alias_id, references("pwm_alias"),
        on_delete: :nilify_all,
        on_update: :update_all
      )
    end
  end
end
