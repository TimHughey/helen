defmodule Repo.Migrations.DropRemoteBattMv do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table("remote") do
      remove(:batt_mv, :integer, default: 0)
    end
  end
end
