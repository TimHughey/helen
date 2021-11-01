defmodule Sally.Repo.Migrations.ConvertIndexesToBtree do
  use Ecto.Migration

  def change do
    drop_if_exists(index(:datapoint, [:reading_at]))
    create(index(:datapoint, [:reading_at]))

    drop_if_exists(index(:command, [:sent_at]))
    create(index(:command, [:sent_at]))
  end
end
