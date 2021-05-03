defmodule Repo.Migrations.AddHelenModuleConfig do
  use Ecto.Migration

  def change do
    create(table("helen_mod_config")) do
      add(:module, :string, null: false)
      add(:description, :string, default: "<none>")
      add(:opts, :text, default: "[]", null: false)
      add(:version, :uuid, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:helen_mod_config, [:module], unique: true))
  end
end
