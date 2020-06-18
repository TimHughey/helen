defmodule Repo.Migrations.EliminateDutycycleTables do
  use Ecto.Migration

  def change do
    drop(table("dutycycle_profile"))
    drop(table("dutycycle_state"))
    drop(table("dutycycle"))
  end
end
